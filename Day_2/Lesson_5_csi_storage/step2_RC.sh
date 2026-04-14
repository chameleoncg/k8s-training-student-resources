#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"

NS="default"
CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
EXPECTED_PROVISIONER="rook-ceph.rbd.csi.ceph.com"

SUFFIX="$(date +%s)"
PVC_NAME="rook-ceph-verify-pvc-${SUFFIX}"
POD_NAME="rook-ceph-verify-writer-${SUFFIX}"

echo "--- [Script2] Rook-Ceph Verification (unique per run) ---"

echo "--- 0. Wait for CSIDriver registration (bounded) ---"
timeout_seconds=600
start_ts=$(date +%s)

until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for CSIDriver: $CSIDRIVER_NAME"
    kubectl --context "$KIND_CONTEXT" get csidriver || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster my-cluster | tail -n 120 || true
    exit 1
  fi
  echo "Waiting for CSIDriver..."
  sleep 5
done
echo "CSIDriver registered: $CSIDRIVER_NAME"

echo "--- 1. Choose StorageClass (prefer rbd-nbd) ---"
if kubectl --context "$KIND_CONTEXT" get sc rook-ceph-block-nbd >/dev/null 2>&1; then
  RC_SC="rook-ceph-block-nbd"
else
  RC_SC="rook-ceph-block"
fi

echo "Using StorageClass: $RC_SC"
kubectl --context "$KIND_CONTEXT" get sc "$RC_SC" >/dev/null

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

echo "--- 4. Wait for PVC Bound (bounded) ---"
if ! kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m; then
  echo "ERROR: PVC did not bind. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n "$NS" get events --sort-by=.metadata.creationTimestamp | tail -n 120 || true
  exit 1
fi

echo "--- 5. Wait for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m

echo "--- 6. Read evidence file back ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"