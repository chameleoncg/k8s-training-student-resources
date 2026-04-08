#!/bin/bash
# Script: kind + Local Path Provisioner (no Longhorn)

set -euo pipefail

# -------------------------
# 0) Host kernel / limits (optional but kept)
# -------------------------
echo "--- 0. Optimizing Host Resource Limits & Kernel ---"

sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

# Persist settings across reboots.
grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

echo "Host limits and kernel forwarding optimized."

# -------------------------
# 0b) Restart container runtime (best-effort)
# -------------------------
echo "--- 0b. Refreshing Container Runtime ---"
sudo systemctl daemon-reload
sudo systemctl restart docker

# -------------------------
# 1) kind cluster config
# -------------------------
echo "--- 1. Creating Kind 2-Node Configuration (1 control-plane, 1 worker) ---"

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
  # Local-path does not require iSCSI mounts/devices.
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = false
EOF

# -------------------------
# 2) Create the kind cluster
# -------------------------
echo "--- 2. Building 2-Node Kubernetes Cluster ---"

kind delete cluster --name longhorn-lab || true
docker network prune -f || true

kind create cluster --name longhorn-lab --config kind-config.yaml --wait 15m

# Wait for Kubernetes nodes to be Ready.
echo "--- Verification: Check if nodes are online ---"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
echo "Cluster nodes are Ready."

# -------------------------
# 3) Ensure Local Path Provisioner is installed
# -------------------------
echo "--- 3. Ensuring Local Path Provisioner is installed ---"

# Check if local-path-provisioner exists (common in kind).
if kubectl -n kube-system get deploy local-path-provisioner >/dev/null 2>&1; then
  echo "Local path provisioner deployment already exists."
else
  echo "Local path provisioner not found; installing it..."
  # Kind commonly uses this local-path-provisioner; install explicitly if missing.
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi

kubectl -n kube-system rollout status deploy/local-path-provisioner --timeout=180s || true
kubectl -n kube-system get pods | grep -i local-path || true

# -------------------------
# 4) Configure default StorageClass to Local Path
# -------------------------
echo "--- 4. Setting Local Path StorageClass as default ---"

echo "Current StorageClasses:"
kubectl get sc

# Common name is "standard" for local-path provisioner in kind.
# If it differs in your environment, adjust STD_SC accordingly.
STD_SC="standard"

# If "standard" doesn't exist, try to find any storageclass using rancher.io/local-path.
if ! kubectl get sc "${STD_SC}" >/dev/null 2>&1; then
  echo "StorageClass '${STD_SC}' not found; detecting local-path SC..."
  STD_SC="$(kubectl get sc -o name | xargs -n1 -I{} kubectl get {} -o jsonpath='{.metadata.name}{"\t"}{.provisioner}{"\n"}' \
    | awk '$2 ~ /local-path/ {print $1; exit}')"
fi

if [ -z "${STD_SC}" ]; then
  echo "ERROR: Could not determine Local Path StorageClass name."
  exit 1
fi

echo "Using Local Path StorageClass: ${STD_SC}"

# Remove default annotation from all SCs
kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
| awk '$2=="true"{print $1}' \
| while read -r sc; do
    kubectl patch storageclass "$sc" \
      -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
  done

# Set target SC as default
kubectl patch storageclass "${STD_SC}" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

echo "Updated StorageClasses:"
kubectl get sc

# -------------------------
# 5) Quick “done” validation: write /data/hello.txt to a PVC
# -------------------------
echo "--- 5. Quick verification: write /data/hello.txt to PVC ---"

cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: localpath-hello-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${STD_SC}
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