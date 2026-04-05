#!/bin/bash
set -euo pipefail

PVC_NAME="longhorn-verify-pvc"
POD_NAME="storage-checker"
LH_NS="longhorn-system"

echo "--- 1. Patch Longhorn for 2-Node Environment (replicas=2) ---"
kubectl -n "$LH_NS" patch settings.longhorn.io default-replica-count \
  --type merge -p '{"value":"2"}'

echo "--- 2. Patch StorageClass (force replicas=2) ---"
kubectl patch storageclass longhorn --type merge \
  -p '{"parameters":{"numberOfReplicas":"2"}}' || true
kubectl patch storageclass longhorn --type merge \
  -p '{"parameters":{"replicaCount":"2"}}' || true

echo "Current StorageClass:"
kubectl get sc longhorn -o yaml | sed -n '1,200p' || true

echo "--- 3. (Determinism) Delete any existing Longhorn Volume tied to this PVC ---"
# In your earlier output, the label was: longhornvolume=pvc-<...>
# Here we delete any Longhorn volume that references the same PVC name.
# (If none exist, this is a no-op.)
EXISTING_VOLUMES="$(kubectl -n "$LH_NS" get volumes.longhorn.io \
  -l "longhornvolume=${PVC_NAME}" -o name 2>/dev/null || true)"

if [ -n "$EXISTING_VOLUMES" ]; then
  echo "Deleting existing Longhorn volumes: $EXISTING_VOLUMES"
  kubectl -n "$LH_NS" delete $EXISTING_VOLUMES --ignore-not-found=true || true
else
  echo "No existing Longhorn Volume found for label longhornvolume=${PVC_NAME}."
fi

echo "--- 4. Recreate PVC + Pod (avoid delete/create race) ---"
kubectl delete pod "$POD_NAME" --ignore-not-found=true || true
kubectl delete pvc "$PVC_NAME" --ignore-not-found=true || true

# Wait briefly for PVC deletion to settle
kubectl wait --for=delete "pvc/${PVC_NAME}" -n default --timeout=60s || true

echo "--- 5. Create PVC ---"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

echo "--- 6. Deploy Test Pod ---"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
EOF

echo "--- 7. Wait for PVC Bound ---"
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" --timeout=180s
kubectl get pvc "$PVC_NAME"

echo "--- 8. Wait for Pod Ready (or fail with debug) ---"
if kubectl wait --for=condition=Ready pod/"$POD_NAME" --timeout=240s; then
  echo "Pod became Ready."
else
  echo "Pod did NOT become Ready in time. Debugging:"

  kubectl get pod "$POD_NAME" -o wide || true
  kubectl describe pod "$POD_NAME" | sed -n '/Events:/,$p' || true

  echo "--- Longhorn volumes matching pvc label ---"
  kubectl -n "$LH_NS" get volumes.longhorn.io -l "longhornvolume=${PVC_NAME}" -o wide || true

  echo "Tip: identify the Longhorn volume name above, then run:"
  echo "  kubectl -n $LH_NS describe volumes.longhorn.io <VOLUME_NAME>"
  exit 1
fi

echo "--------------------------------------------------------"
echo "VALIDATION COMPLETE"
echo "Your PVC is BOUND and your Pod is READY."
echo "--------------------------------------------------------"