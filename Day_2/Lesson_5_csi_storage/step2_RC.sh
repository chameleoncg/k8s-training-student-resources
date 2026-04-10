#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- [Script2] Rook-Ceph Verification ---"

# 1. Check if the Rook-Ceph StorageClass is ready
RC_SC="rook-ceph-block"
echo "Checking for StorageClass: $RC_SC..."

if ! kubectl --context "$KIND_CONTEXT" get sc "$RC_SC" &>/dev/null; then
  echo "ERROR: Rook-Ceph StorageClass ($RC_SC) not found! Did Script 1 finish successfully?"
  exit 1
fi

echo "--- 2. Creating PVC and Verification Pod ---"
# We use a unique name to avoid conflicts with previous local-path tests
cat <<YAML | kubectl --context "$KIND_CONTEXT" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rook-ceph-verify-pvc
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
  name: rook-ceph-verify-writer
spec:
  restartPolicy: Never
  containers:
  - name: tester
    image: busybox:1.36
    # Writes a unique timestamped string to the Ceph volume
    command: ["sh","-c","echo 'Ceph-Storage-Verified-\$(date)' > /data/verify.txt; sleep 10"]
    volumeMounts:
    - name: ceph-vol
      mountPath: /data
  volumes:
  - name: ceph-vol
    persistentVolumeClaim:
      claimName: rook-ceph-verify-pvc
YAML

echo "--- 3. Waiting for Volume Attachment (RBD Mapping) ---"
# Ceph takes longer than local-path because it must map a network block device.
echo "Waiting for pod to reach 'Running' or 'Completed' state..."
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready pod/rook-ceph-verify-writer --timeout=300s

echo "--- 4. Verifying Data Integrity ---"
# Read the file back to prove the write succeeded on the Ceph RBD
FILE_CONTENT=$(kubectl --context "$KIND_CONTEXT" exec pod/rook-ceph-verify-writer -- cat /data/verify.txt)

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"

# Optional: Cleanup
# kubectl --context "$KIND_CONTEXT" delete pod rook-ceph-verify-writer
# kubectl --context "$KIND_CONTEXT" delete pvc rook-ceph-verify-pvc