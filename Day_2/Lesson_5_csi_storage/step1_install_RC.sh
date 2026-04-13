#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"
CEPH_CLUSTER_NAME="my-cluster"

echo "--- 0. Repairing any interrupted dpkg/apt state ---"
sudo dpkg --configure -a || true
sudo apt -f install -y || true

echo "--- 1. Updating Package Index & Installing Host Dependencies ---"
sudo apt update
sudo apt install -y docker.io lvm2 thin-provisioning-tools linux-modules-extra-$(uname -r)
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
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev
    containerPath: /dev
EOF

kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml --wait 0s

echo "--- 5. Waiting for Nodes Ready ---"
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=300s

echo "--- 6. Installing Rook-Ceph Operator (pinned release) ---"
ROOK_URL="https://raw.githubusercontent.com/rook/rook/release-1.13/deploy/examples"

kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/common.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/crds.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/operator.yaml"

echo "Waiting for rook-ceph-operator..."
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "Waiting for ceph-csi-controller-manager..."
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/ceph-csi-controller-manager --timeout=600s

echo "--- 6.1. Ensuring WATCH_NAMESPACE is set on CSI controller-manager ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" set env deployment/ceph-csi-controller-manager WATCH_NAMESPACE="$ROOK_NS" >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout restart deployment/ceph-csi-controller-manager >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/ceph-csi-controller-manager --timeout=600s

echo "--- 7. Installing Rook-Ceph Cluster (Test Mode) ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 7.1. Patching CephCluster image to satisfy squid minimum ---"
# Your lab’s detect-version gate wanted 19.2.0-0 squid.
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19.2.0"}}}' >/dev/null 2>&1 || true

echo "--- 8. Installing RBD StorageClass ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/csi/rbd/storageclass-test.yaml"

# Set rook-ceph-block as default SC (idempotent best-effort)
kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "--- 9. Waiting for CSIDriver registration (bounded) ---"
CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
timeout_seconds=900
start_ts=$(date +%s)

until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  now_ts=$(date +%s)
  elapsed=$(( now_ts - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for CSIDriver: $CSIDRIVER_NAME"
    echo "---- CephCluster status ----"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster "$CEPH_CLUSTER_NAME" | tail -n 120 || true
    echo "---- CSI controller logs ----"
    POD=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o name | grep ceph-csi-controller-manager | head -n1 || true)
    if [ -n "$POD" ]; then kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" logs "${POD#pod/}" --tail=200 || true; fi
    echo "---- CSI CSIDrivers ----"
    kubectl --context "$KIND_CONTEXT" get csidriver || true
    exit 1
  fi
  echo "Waiting for CSIDriver $CSIDRIVER_NAME ..."
  sleep 5
done

echo "CSIDriver registered: $CSIDRIVER_NAME"

echo "--------------------------------------------------------"
echo "ROOK-CEPH INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
echo "--------------------------------------------------------"