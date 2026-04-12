#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

ROOK_NS="rook-ceph"
NS="default"
PVC_NAME="rook-ceph-verify-pvc"
POD_NAME="rook-ceph-verify-writer"

CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
EXPECTED_PROVISIONER="rook-ceph.rbd.csi.ceph.com"

echo "--- [Script2] Rook-Ceph Verification ---"

echo "--- 0. Confirm CSIDriver exists (bounded) ---"
timeout_seconds=300
start_ts=$(date +%s)
until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  now_ts=$(date +%s)
  elapsed=$(( now_ts - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: CSIDriver not registered: $CSIDRIVER_NAME"
    kubectl --context "$KIND_CONTEXT" get csidriver || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster my-cluster | tail -n 80 || true
    exit 1
  fi
  echo "Waiting for CSIDriver $CSIDRIVER_NAME ..."
  sleep 5
done
echo "CSIDriver is present."

echo "--- 1. Discover StorageClass by provisioner ---"
RC_SC="$(
  kubectl --context "$KIND_CONTEXT" get storageclass \
    -o jsonpath='{range .items[?(@.provisioner=="'"$EXPECTED_PROVISIONER"'")]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | head -n 1 | tr -d '\r'
)"

if [ -z "$RC_SC" ]; then
  echo "ERROR: No StorageClass found with provisioner $EXPECTED_PROVISIONER"
  kubectl --context "$KIND_CONTEXT" get storageclass || true
  exit 1
fi

echo "Using StorageClass: $RC_SC"

echo "--- 2. Cleanup old resources (safe) ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true

echo "--- 3. Create PVC + verification Pod ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${RC_SC}
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
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
      claimName: ${PVC_NAME}
YAML

echo "--- 4. Wait for PVC Bound ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m || {
  echo "ERROR: PVC did not bind. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide || true
  kubectl --context "$KIND_CONTEXT" get csidriver || true
  exit 1
}

echo "--- 5. Wait for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m || {
  echo "ERROR: Pod not Ready. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pod/"$POD_NAME" || true
  exit 1
}

echo "--- 6. Verify file write/read ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"