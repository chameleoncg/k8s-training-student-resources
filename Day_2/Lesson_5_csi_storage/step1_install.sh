#!/bin/bash
set -e

CLUSTER_NAME="localpath-lab"

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

echo "--- Creating kind cluster ---"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --wait 120s

echo "--- Ensuring Local Path Provisioner is installed (smart namespace detection) ---"

# Detect if the deployment already exists in either namespace.
LP_NS="$(kubectl get deploy local-path-provisioner -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n1 || true)"

if [ -z "$LP_NS" ]; then
  echo "Local Path provisioner not found. Installing into kube-system..."

  # Download YAML and rewrite namespace: default -> kube-system (so both scripts agree).
  kubectl apply -f <(curl -fsSL https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml \
    | sed 's/namespace: default/namespace: kube-system/g')
  LP_NS="kube-system"
else
  echo "Found local-path-provisioner in namespace: $LP_NS (skipping install)."
fi

echo "--- Waiting for local-path provisioner ---"
kubectl -n "$LP_NS" rollout status deploy/local-path-provisioner --timeout=180s || true
kubectl -n "$LP_NS" get pods | grep -i local-path || true

echo "--- Setting StorageClass default (detect by provisioner) ---"
LP_SC="$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.provisioner}{"\n"}{end}' \
  | awk -F'\t' '$2 ~ /rancher.io\/local-path/ {print $1; exit}')"

if [ -z "$LP_SC" ]; then
  echo "ERROR: Could not detect Local Path StorageClass (provisioner rancher.io/local-path)."
  exit 1
fi

# Remove default from any existing default SCs
kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
  | awk -F'\t' '$2=="true"{print $1}' \
  | while read -r sc; do
      kubectl patch storageclass "$sc" \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
    done

kubectl patch storageclass "$LP_SC" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "Local Path StorageClass defaulted to: $LP_SC"

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "IMPORTANT: Log out/in (or run: newgrp docker) so your user picks up the docker group."
echo "Cluster: $CLUSTER_NAME"
echo "--------------------------------------------------------"