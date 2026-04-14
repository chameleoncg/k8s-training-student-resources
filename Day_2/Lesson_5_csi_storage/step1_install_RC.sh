#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"
CEPH_CLUSTER_NAME="my-cluster"

echo "--- 0. Repair any interrupted dpkg/apt state ---"
sudo dpkg --configure -a || true
sudo apt -f install -y || true

echo "--- 1. Host deps ---"
sudo apt update
sudo apt install -y docker.io lvm2 thin-provisioning-tools linux-modules-extra-$(uname -r)
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

echo "--- 1.1 Install loopback helpers (util-linux) ---"
sudo apt-get update -y >/dev/null 2>&1 || true
sudo apt-get install -y util-linux >/dev/null 2>&1 || true

echo "--- 1.2 Create a dedicated, zero-filled loop device for OSDs ---"
LOOP_IMG="/tmp/rook-ceph-loop.img"
LOOP_SIZE="20G"

sudo rm -f "$LOOP_IMG" || true
sudo losetup -D || true

# Use fully zero-filled file for deterministic bluestore probing.
sudo dd if=/dev/zero of="$LOOP_IMG" bs=1M count=20480 conv=fsync status=progress

sudo losetup -fP "$LOOP_IMG"

LOOP_DEV_NAME="$(sudo losetup -j "$LOOP_IMG" | awk -F: '{print $1}' | head -n1)"
LOOP_KNAME="$(basename "$LOOP_DEV_NAME")"

echo "Created loop device: $LOOP_DEV_NAME (kname=$LOOP_KNAME)"

echo "--- 2. Install kind & kubectl ---"
if ! command -v kind &>/dev/null; then
  curl -fLo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &>/dev/null; then
  sudo snap install kubectl --classic
fi

echo "--- 3. Create kind cluster ---"
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

echo "--- 4. Wait for nodes Ready ---"
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=300s

echo "--- 5. Install rook-ceph (pinned release) ---"
ROOK_URL="https://raw.githubusercontent.com/rook/rook/release-1.13/deploy/examples"

kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/common.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/crds.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/operator.yaml"

echo "Waiting for rook-ceph-operator..."
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 5.1 Enable loop devices in operator CONFIGMAP (needed for loop OSDs) ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch configmap rook-ceph-operator-config \
  --type merge \
  -p '{"data":{"ROOK_CEPH_ALLOW_LOOP_DEVICES":"true"}}' >/dev/null 2>&1 || true

# Ensure RBD CSI integration is enabled
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch configmap rook-ceph-operator-config \
  --type merge \
  -p '{"data":{"ROOK_CSI_ENABLE_RBD":"true","ROOK_USE_CSI_OPERATOR":"true","ROOK_CSI_DISABLE_DRIVER":"false"}}' >/dev/null 2>&1 || true

kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout restart deployment/rook-ceph-operator || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 6. Apply CephCluster (test mode) ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 6.1 Patch Ceph version for squid minimum ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19.2.0"}}}' >/dev/null 2>&1 || true

echo "--- 6.2 Restrict CephCluster to ONLY /dev/${LOOP_KNAME} ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p "{\"spec\":{\"storage\":{\"useAllDevices\":false,\"deviceFilter\":\"\",\"devices\":[{\"name\":\"/dev/${LOOP_KNAME}\"}]}}}" \
  >/dev/null 2>&1 || true

echo "--- 7. Apply RBD StorageClass (kernel rbd mounter, lesson default) ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/csi/rbd/storageclass-test.yaml"

echo "--- 7.1 Set rook-ceph-block as default StorageClass ---"
kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "--- 7.2 Create alternate RBD StorageClass using rbd-nbd mounter (fixes modprobe/rbd) ---"
kubectl --context "$KIND_CONTEXT" apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block-nbd
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  mounter: rbd-nbd
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
YAML

echo "--- 8. Wait for Ceph MON + OSD daemon ready (quorum-style) ---"
timeout_seconds=1800
start_ts=$(date +%s)

while true; do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for MON + OSD daemon."
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods | egrep 'rook-ceph-(mon|osd|osd-prepare)' || true
    exit 1
  fi

  mon_running=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
    | awk '$1 ~ /^rook-ceph-mon/ && $2=="1\/1" && $3=="Running"{c++} END{print (c?c:0)}')

  osd_daemons=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
    | awk '$1 ~ /^rook-ceph-osd-[0-9]+-/ && $2=="1\/1" && $3=="Running"{c++} END{print (c?c:0)}')

  echo "  [${elapsed}s] MON Running: ${mon_running} | OSD daemon ready: ${osd_daemons}"

  if [ "${mon_running}" -ge 1 ] && [ "${osd_daemons}" -ge 1 ]; then
    echo "--- MON running and OSD daemon is ready ---"
    break
  fi

  sleep 10
done

echo "--- 9. Wait for CephBlockPool replicapool to be Ready ---"
until kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool -o jsonpath='{.status.phase}' 2>/dev/null | grep -q '^Ready$'; do
  echo -n "."
  sleep 5
done
echo ""

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool
kubectl --context "$KIND_CONTEXT" get storageclass | egrep 'rook-ceph-(block|block-nbd)' || true
echo "--------------------------------------------------------"