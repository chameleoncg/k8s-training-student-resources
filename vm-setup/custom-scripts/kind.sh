#!/usr/bin/env bash

# enable unofficial bash strict mode
set -o errexit
set -o nounset
set -o pipefail
shopt -s extglob

IFS=$'\n\t'

# =======directory paths=======
LOCAL_DIR="$(realpath $0 | sed 's|\(.*\)/.*|\1|')"
ROOT_DIR="${LOCAL_DIR%/scripts?(/*)}"
# =======logging functions=======
_INFO="\e[1;36m"  # Bold Cyan
_WARN="\e[1;33m"  # Bold Yellow
_SUCCESS="\e[1;32m"  # Bold Green
_ERROR="\e[1;31m"  # Bold Red
_CLR="\e[0m"  # Clear ANSI Codes

info() {
  printf "${_INFO}%s${_CLR}\n" "$1"
}

warn() {
  printf "${_WARN}%s${_CLR}\n" "$1"
}

success() {
  printf "${_SUCCESS}%s${_CLR}\n" "$1"
}

error() {
  printf "${_ERROR}%s${_CLR}\n" "$1"
}

fatal() {
  error "$@"; exit 1
}

# =======kind functions=======
CLUSTER_NAME='lab-cluster'
REGISTRY_NAME="${REGISTRY_NAME:="lab.registry"}"
REGISTRY_PORT="${REGISTRY_PORT:="5050"}"
REGISTRY_INTERNAL_PORT="${REGISTRY_INTERNAL_PORT:="5000"}"

KIND_CNI="cilium"
case "${KIND_CNI}" in
  "default" )
    DISABLE_DEFAULT_CNI="false"
    ;;
  "cilium" )
    DISABLE_DEFAULT_CNI="true"
    ;;
  * )
    fatal "Only supported values for KIND_CNI at this time are 'default' and 'cilium'"
    ;;
esac

CILIUM_VERSION="1.15.5"
HUBBLE_VERSION="0.13.0"

create_cluster() {
  # check for cgroups v2 installed (required for cilium socketLB)
  if ! grep cgroup2 /proc/filesystems >/dev/null; then
    error "cgroup v2 needs to be enabled for Cilium's Socket LB"
    error "Please enable cgroup v2 by running:\n"
    error "  sudo sysctl -w systemd.unified_cgroup_hierarchy=1"
    exit 1
  fi

  if [ -z "$(kind get clusters 2>/dev/null | grep "$CLUSTER_NAME")" ]; then
    local cluster_domain="lab.cluster"
    info "Creating kind cluster: ${CLUSTER_NAME}"
    info "Setting cluster kube-apiserver to cluster.${cluster_domain}"
    tmp_config=$(mktemp)
    cat << EOL > $tmp_config
    apiVersion: kind.x-k8s.io/v1alpha4
    kind: Cluster
    containerdConfigPatches:
      - |-
        [plugins."io.containerd.grpc.v1.cri".registry]
          config_path = "/etc/containerd/certs.d"
    kubeadmConfigPatches:
      - |-
        kind: ClusterConfiguration
        apiServer:
          certSANs:
            - cluster.${cluster_domain}
            - "0.0.0.0"
    networking:
      apiServerAddress: "0.0.0.0"
      apiServerPort: 6443
      disableDefaultCNI: ${DISABLE_DEFAULT_CNI}
      podSubnet: "10.244.0.0/16"
      serviceSubnet: "10.96.0.0/12"
      kubeProxyMode: none
    nodes:
      - role: control-plane
        image: docker.io/kindest/node:v1.30.2
        extraMounts:
          - hostPath: /etc/ssl/certs/ca-certificates.crt
            containerPath: /etc/ssl/certs/ca-certificates.crt
        kubeadmConfigPatches:
          - |
            kind: ClusterConfiguration
            controllerManager:
              extraArgs:
                "bind-address": "0.0.0.0"
            scheduler:
              extraArgs:
                "bind-address": "0.0.0.0"
            etcd:
              local:
                extraArgs:
                  "listen-metrics-urls": "http://0.0.0.0:2381"
      - role: worker
        image: docker.io/kindest/node:v1.30.2
        extraMounts:
          - hostPath: /etc/ssl/certs/ca-certificates.crt
            containerPath: /etc/ssl/certs/ca-certificates.crt
        extraPortMappings:
          - containerPort: 30080
            hostPort: 80
            listenAddress: 0.0.0.0
          - containerPort: 30443
            hostPort: 443
            listenAddress: 0.0.0.0
          - containerPort: 31235
            hostPort: 31235
            listenAddress: 0.0.0.0
EOL
    cat "$tmp_config" | kind create cluster --name "${CLUSTER_NAME}" --config=-; rm "$tmp_config"
    REGISTRY_DIR="containerd/certs.d/${REGISTRY_NAME}:5000"
    for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
      docker exec "${node}" mkdir -p "/etc/${REGISTRY_DIR}"
      cat "${ROOT_DIR}/.registry/${REGISTRY_DIR}/hosts.toml" | docker exec -i "${node}" cp /dev/stdin "/etc/${REGISTRY_DIR}/hosts.toml"
    done
    cat <<EOF | kubectl apply --server-side -f-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: local-registry-hosting
      namespace: kube-public
    data:
      localRegistryHosting.v1: |
        host: "localhost:${REGISTRY_PORT}"
        hostFromContainerRuntime: "${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"
        hostFromClusterNetwork: "${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"
        help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
  fi

  if [[ "${KIND_CNI}" == "cilium" ]] && ! helm -n kube-system status cilium >/dev/null 2>&1; then
    echo "Installing cilium (v${CILIUM_VERSION})"
    cat <<EOF | helm install -n kube-system cilium "https://helm.cilium.io/cilium-1.15.4.tgz" --values -
    kubeProxyReplacement: true
    k8sServiceHost: "${CLUSTER_NAME}-control-plane"
    k8sServicePort: 6443
    ipam:
      mode: kubernetes
    ipv4:
      enabled: true
    ipv6:
      enabled: false
    socketLB:
      hostNamespaceOnly: true
    cni:
      exclusive: false
    hubble:
      enabled: true
      relay:
        enabled: true
        image:
          repository: docker.io/rancher/mirrored-cilium-hubble-relay
          tag: v${CILIUM_VERSION}
          useDigest: false
      ui:
        enabled: true
        service:
          type: NodePort
          nodePort: 31235
        backend:
          image:
            repository: docker.io/rancher/mirrored-cilium-hubble-ui-backend
            tag: v${HUBBLE_VERSION}
            useDigest: false
        frontend:
          image:
            repository: docker.io/rancher/mirrored-cilium-hubble-ui
            tag: v${HUBBLE_VERSION}
            useDigest: false
          server:
            ipv6:
              enabled: false
    image:
      repository: docker.io/rancher/mirrored-cilium-cilium
      tag: v${CILIUM_VERSION}
      useDigest: false
    operator:
      image:
        repository: docker.io/rancher/mirrored-cilium-operator
        tag: v${CILIUM_VERSION}
        useDigest: false
EOF
    info "Waiting for kube-system pods to come up ready, please be patient. This can take up to 5 minutes due to Cilium."
    kubectl wait --for=condition=Ready nodes --all --timeout=5m
  fi
  if [[ "$(kubectl config current-context)" != "kind-${CLUSTER_NAME}" ]]; then
    kubectl config set-context "kind-$CLUSTER_NAME"
  fi
  if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "local-registry" 2>/dev/null)" = 'null' ]; then
    echo "Connecting the docker-registry to the cluster network"
    docker network connect "kind" "local-registry"
  fi
}

delete_cluster() {
  # capi.sh tags namespaces with kind-deprovision/action=delete this makes ensure we delete any lingering clusters it has provisioned.
  #kubectl get namespaces --selector=kind-deprovision/action=delete --output=jsonpath='{.items[*].metadata.name}' | xargs -I {} sh -c "kubectl delete namespace {} || true"
  kind delete cluster --name "${CLUSTER_NAME}" || true
  # clean deletes the kind network from the VM, removing the local-registry if it's lingering.
  docker network inspect -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' kind | xargs -I {} sh -c "docker network disconnect -f kind {} || true"
  docker network rm -f kind || true
}

help (){
  echo "Script for the provisioning of kind clusters
  -i                          Creates a kind cluster
  -s                          Stops any existing kind cluster
  "
}

if (( ${#@} > 0 )); then
  while getopts ":is" option; do
    case $option in
      i)
        create_cluster
        ;;
      s)
        delete_cluster
        ;;
      *)
        help
        ;;
    esac
  done
else
  help
  exit 0
fi