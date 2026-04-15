#!/bin/bash
set -euo pipefail

CLUSTER_NAME="localpath-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"   # IMPORTANT: kubectl context name

echo "--- Updating Package Index ---"
sudo apt update

echo "--- Installing Docker ---"
sudo apt install -y docker.io
sudo systemctl enable --now docker

echo "--- Ensuring current user can run docker ---"
sudo usermod -aG docker "$USER"

echo "--- Installing KiND ---"
curl -fLo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

echo "--- Installing kubectl ---"
sudo snap install kubectl --classic

echo "--- Verifying ---"
docker --version
kind version
kubectl version --client

echo "--- Creating kind cluster (no kind --wait; we will kubectl-wait) ---"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --wait 0s

echo "--- Setting kube context and waiting for nodes Ready ---"
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=300s
kubectl --context "$KIND_CONTEXT" get nodes

echo "--- Ensuring Local Path Provisioner is installed (smart namespace detection) ---"

# detect namespace where deployment exists
LP_NS="$(kubectl --context "$KIND_CONTEXT" get deploy local-path-provisioner -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n1 || true)"

if [ -z "$LP_NS" ]; then
  echo "Local path provisioner not found; installing into kube-system..."
  kubectl --context "$KIND_CONTEXT" apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

  LP_NS="kube-system"
fi

echo "Local path provisioner namespace: $LP_NS"

# Wait in the correct namespace (fixes your NotFound-from-default bug)
kubectl --context "$KIND_CONTEXT" -n "$LP_NS" rollout status deploy/local-path-provisioner --timeout=180s || true
kubectl --context "$KIND_CONTEXT" -n "$LP_NS" get pods | grep -i local-path || true

echo "--- Setting StorageClass default (detect by provisioner) ---"
LP_SC="$(kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.provisioner}{"\n"}{end}' \
  | awk -F'\t' '$2 ~ /rancher.io\/local-path/ {print $1; exit}')"

if [ -z "$LP_SC" ]; then
  echo "ERROR: Could not detect Local Path StorageClass (rancher.io/local-path)."
  exit 1
fi

# Clear default from any SC
kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
| awk -F'\t' '$2=="true"{print $1}' \
| while read -r sc; do
    kubectl --context "$KIND_CONTEXT" patch storageclass "$sc" \
      -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
  done

# Set our SC default
kubectl --context "$KIND_CONTEXT" patch storageclass "$LP_SC" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "Local Path default StorageClass set to: $LP_SC"

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
echo "--------------------------------------------------------"