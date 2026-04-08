#!/bin/bash
set -euo pipefail

CLUSTER_NAME="localpath-lab"

echo "--- 0) Optimizing Host Resource Limits & Kernel (optional) ---"
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

echo "--- 0b) Refreshing Container Runtime (best-effort) ---"
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "--- 1) Creating kind cluster ---"

cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        cgroup-driver: cgroupfs
- role: worker
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        cgroup-driver: cgroupfs
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = false
EOF

kind delete cluster --name "$CLUSTER_NAME" || true
docker network prune -f || true
kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml --wait 15m

echo "--- Verification: nodes ready ---"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes

echo "--- 2) Ensuring Local Path Provisioner installed (smart) ---"

LP_NS="$(kubectl get deploy local-path-provisioner -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n1 || true)"
if [ -z "$LP_NS" ]; then
  echo "Local Path provisioner not found. Installing into kube-system..."
  kubectl apply -f <(curl -fsSL https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml \
    | sed 's/namespace: default/namespace: kube-system/g')
  LP_NS="kube-system"
else
  echo "Found local-path-provisioner in namespace: $LP_NS (skipping install)."
fi

kubectl -n "$LP_NS" rollout status deploy/local-path-provisioner --timeout=180s || true

echo "--- 3) Configure default StorageClass (detect by provisioner) ---"

LP_SC="$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.provisioner}{"\n"}{end}' \
  | awk -F'\t' '$2 ~ /rancher.io\/local-path/ {print $1; exit}')"

if [ -z "$LP_SC" ]; then
  echo "ERROR: Could not detect Local Path StorageClass."
  exit 1
fi

kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
  | awk -F'\t' '$2=="true"{print $1}' \
  | while read -r sc; do
      kubectl patch storageclass "$sc" \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
    done

kubectl patch storageclass "$LP_SC" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "Using Local Path StorageClass: $LP_SC"

echo "--- 4) Quick “done” verification: write /data/hello.txt ---"

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: localpath-hello-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${LP_SC}
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: localpath-hello-writer
spec:
  restartPolicy: Never
  containers:
  - name: t
    image: busybox:1.36
    command: ["sh","-c","echo hello-$(date) > /data/hello.txt; sleep 5"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: localpath-hello-pvc
YAML

kubectl wait --for=condition=Ready pod/localpath-hello-writer --timeout=120s || true
kubectl exec pod/localpath-hello-writer -- sh -lc 'cat /data/hello.txt'

echo "DONE: wrote /data/hello.txt via Local Path Provisioner PVC."