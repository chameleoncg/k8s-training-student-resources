#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

NS="default"
PVC_NAME="rook-ceph-verify-pvc"
POD_NAME="rook-ceph-verify-writer"

# Pinned to avoid master/version drift
ROOK_SC_URL="https://raw.githubusercontent.com/rook/rook/release-1.13/deploy/examples/csi/rbd/storageclass-test.yaml"
CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
EXPECTED_PROVISIONER="rook-ceph.rbd.csi.ceph.com"

echo "--- [Script2] Rook-Ceph Verification ---"

# 0) Ensure StorageClass exists (auto-install if missing)
echo "--- 0. Detecting Rook RBD StorageClass ---"
SC_BY_PROVISIONER="$(
  kubectl --context "$KIND_CONTEXT" get storageclass -o jsonpath='{range .items[?(@.provisioner=="'"$EXPECTED_PROVISIONER"'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
)"

if [ -z "$SC_BY_PROVISIONER" ]; then
  echo "Rook RBD StorageClass missing. Applying it now..."
  kubectl --context "$KIND_CONTEXT" apply -f "$ROOK_SC_URL"
  sleep 2
  SC_BY_PROVISIONER="$(
    kubectl --context "$KIND_CONTEXT" get storageclass -o jsonpath='{range .items[?(@.provisioner=="'"$EXPECTED_PROVISIONER"'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"
fi

RC_SC="$(echo "$SC_BY_PROVISIONER" | head -n 1 | tr -d '\r')"

if [ -z "$RC_SC" ]; then
  echo "ERROR: Still could not find a StorageClass with provisioner $EXPECTED_PROVISIONER."
  echo "Current StorageClasses:"
  kubectl --context "$KIND_CONTEXT" get storageclass || true
  exit 1
fi

echo "Using StorageClass: $RC_SC"

# 1) Wait for CSI driver registration (otherwise PVC will stay Pending forever)
echo "--- 1. Waiting for CSIDriver registration: $CSIDRIVER_NAME ---"
until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  echo "Waiting..."
  sleep 3
done
echo "CSIDriver is registered."

# 2) Cleanup old resources (safe)
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true

# 3) Create PVC + verification Pod
echo "--- 2. Creating PVC and Verification Pod ---"
cat <<YAML | kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: $RC_SC
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  restartPolicy: Never
  containers:
  - name: tester
    image: busybox:1.36
    command:
      - sh
      - -c
      - 'echo "Ceph-Storage-Verified-$(date -u)" > /data/verify.txt; sleep 10'
    volumeMounts:
    - name: ceph-vol
      mountPath: /data
  volumes:
  - name: ceph-vol
    persistentVolumeClaim:
      claimName: $PVC_NAME
YAML

# 4) Wait for PVC Bound
echo "--- 3. Waiting for PVC to be Bound ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m || {
  echo "ERROR: PVC did not bind. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n rook-ceph get pods || true
  kubectl --context "$KIND_CONTEXT" get csidriver || true
  exit 1
}

# 5) Wait for Pod Ready
echo "--- 4. Waiting for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m

# 6) Verify readback
echo "--- 5. Verifying data integrity ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"