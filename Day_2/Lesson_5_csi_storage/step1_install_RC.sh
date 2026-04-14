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
sudo apt install -y docker.io lvm2 thin-provisioning-tools linux-modules-extra-$(uname -r) util-linux udev >/dev/null
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

echo "--- 1.0 Ensure kernel modules likely needed are present ---"
# rbd + nbd are the typical needs for this lab setup.
# (If modprobe fails, we keep going; script will still diagnose CSI/node issues later.)
sudo modprobe nbd max_part=8 || true
sudo modprobe rbd || true

echo "--- 1.1 Install util-linux (for losetup/loop mgmt) ---"
sudo apt-get install -y util-linux >/dev/null 2>&1 || true

echo "--- 1.2 Create a dedicated, zero-filled loop device for OSDs ---"
LOOP_IMG="/tmp/rook-ceph-loop.img"
LOOP_SIZE="20G"

sudo rm -f "$LOOP_IMG" || true
sudo losetup -D || true

echo "--- 1.3 Zero-fill loop image (avoid bluestore label garbage) ---"
sudo dd if=/dev/zero of="$LOOP_IMG" bs=1M count=20480 conv=fsync status=progress

sudo losetup -fP "$LOOP_IMG"

LOOP_DEV_NAME="$(sudo losetup -j "$LOOP_IMG" | awk -F: '{print $1}' | head -n1)"
LOOP_KNAME="$(basename "$LOOP_DEV_NAME")"

echo "Created loop device: $LOOP_DEV_NAME (kname=$LOOP_KNAME)"

echo "--- 1.4 udev settle/trigger ---"
sudo udevadm settle || true
sudo udevadm trigger --action=add || true
sudo udevadm settle || true

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
  - hostPath: /sys
    containerPath: /sys
  - hostPath: /run/udev
    containerPath: /run/udev
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

echo "--- 5.1 Enable loop devices + CSI RBD in operator ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch configmap rook-ceph-operator-config \
  --type merge \
  -p '{"data":{"ROOK_CEPH_ALLOW_LOOP_DEVICES":"true","ROOK_CSI_ENABLE_RBD":"true","ROOK_USE_CSI_OPERATOR":"true","ROOK_CSI_DISABLE_DRIVER":"false"}}' >/dev/null 2>&1 || true

kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout restart deployment/rook-ceph-operator || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 6. Apply CephCluster (test mode) ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 6.1 Patch Ceph version for squid minimum ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19.2.0"}}}' >/dev/null 2>&1 || true

echo "--- 6.2 Restrict OSD devices to ONLY /dev/loopX ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p "{\"spec\":{\"storage\":{\"useAllDevices\":false,\"deviceFilter\":\"\",\"devices\":[{\"name\":\"/dev/${LOOP_KNAME}\"}]}}}" >/dev/null 2>&1 || true

echo "--- 7. Apply StorageClasses ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/csi/rbd/storageclass-test.yaml"

kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "--- 7.1 Create rbd-nbd StorageClass to avoid kernel modprobe issues ---"
kubectl --context "$KIND_CONTEXT" apply -f - <<YAML
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

echo "--- 8. Wait for CephBlockPool replicapool to be Ready (timeout + diagnostics) ---"
ROOK_TIMEOUT_SEC=900
deadline=$((SECONDS+ROOK_TIMEOUT_SEC))

while true; do
  phase="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" = "Ready" ]; then
    echo "replicapool Ready"
    break
  fi

  if [ $SECONDS -gt $deadline ]; then
    echo "ERROR: timed out waiting for replicapool Ready (last phase: ${phase:-<none>}). Dumping diagnostics..."
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephcluster "$CEPH_CLUSTER_NAME" -o wide || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephblockpool replicapool || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" logs deploy/rook-ceph-operator --tail=250 || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get jobs || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -l app=rook-ceph-osd -o wide || true
    # dump latest OSD prepare job logs if any jobs exist
    osdjob="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get jobs -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep 'rook-ceph-osd-prepare' | head -n1 || true)"
    if [ -n "${osdjob}" ]; then
      kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" logs "job/${osdjob}" --tail=300 || true
    fi
    exit 1
  fi

  echo -n "."
  sleep 5
done

echo "--------------------------------------------------------"
echo "ROOK-CEPH INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool -o wide
echo "--------------------------------------------------------"