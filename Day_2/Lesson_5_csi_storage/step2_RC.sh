#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- [Script2] Rook-Ceph Verification ---"
RC_SC="rook-ceph-block"
NS="default"
PVC_NAME="rook-ceph-verify-pvc"
POD_NAME="rook-ceph-verify-writer"

kubectl --context "$KIND_CONTEXT" get sc "$RC_SC" >/dev/null || {
  echo "ERROR: StorageClass $RC_SC not found"
  exit 1
}

echo "--- 2. Creating PVC and Verification Pod ---"
cat <<YAML | kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f -
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
    command: ["sh","-c","echo \"Ceph-Storage-Verified-$(date -u)\" > /data/verify.txt; sleep 10"]
    volumeMounts:
    - name: ceph-vol
      mountPath: /data
  volumes:
  - name: ceph-vol
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
YAML

echo "--- 3. Waiting for PVC to bind  ---"
set +e
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "ERROR: PVC did not bind. Dumping diagnostics..."
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n rook-ceph get pods || true
  kubectl --context "$KIND_CONTEXT" get csidriver | egrep 'rook|ceph|rbd' || true
  exit $RC
fi

echo "--- 4. Waiting for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m

echo "--- 5. Verifying data integrity ---"
FILE_CONTENT=$(kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt)
echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"