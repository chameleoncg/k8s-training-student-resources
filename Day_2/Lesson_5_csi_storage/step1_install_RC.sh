#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- 1. Updating Package Index & Installing Host Dependencies ---"
# Rook-Ceph requires lvm2 on the host and extra kernel modules for iSCSI/RBD
sudo apt update
sudo apt install -y docker.io lvm2 linux-modules-extra-$(uname -r)
sudo systemctl enable --now docker

echo "--- 2. Ensuring current user can run docker ---"
sudo usermod -aG docker "$USER" || true

echo "--- 3. Installing KiND & kubectl ---"
if ! command -v kind &> /dev/null; then
    curl -fLo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &> /dev/null; then
    sudo snap install kubectl --classic
fi

echo "--- 4. Creating KiND Cluster with Host Pass-through ---"
# This config is CRITICAL. Without /dev and /lib/modules, Rook cannot see disks.
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev
    containerPath: /dev
  - hostPath: /lib/modules
    containerPath: /lib/modules
EOF

kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml --wait 0s

echo "--- 5. Waiting for Nodes Ready ---"
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=300s

echo "--- 6. Installing Rook-Ceph Operator ---"
ROOK_URL="https://raw.githubusercontent.com/rook/rook/master/deploy/examples"

# Apply Common resources, CRDs, and the Operator
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/common.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/crds.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/operator.yaml"

echo "Waiting for Operator deployment..."
kubectl --context "$KIND_CONTEXT" -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=120s

echo "--- 7. Installing Rook-Ceph Cluster (Test Mode) ---"
# cluster-test.yaml is designed for limited resource environments
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 8. Creating StorageClass & Setting as Default ---"
# storageclass-test.yaml provides 'rook-ceph-block'
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/storageclass-test.yaml"

# Set rook-ceph-block as the default SC
kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "--- 9. Waiting for Ceph Cluster to Initialise ---"
# We wait for the 'replicapool' to show up, indicating the OSDs are up and running
echo "This may take 3-5 minutes depending on your VM speed..."
until kubectl --context "$KIND_CONTEXT" -n rook-ceph get cephblockpool replicapool &>/dev/null; do
    echo -n "."
    sleep 5
done

echo -e "\n--------------------------------------------------------"
echo "ROOK-CEPH INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
echo "Note: Monitor pods with: kubectl get pods -n rook-ceph"
echo "--------------------------------------------------------"