#!/bin/bash
set -euo pipefail

PVC_NAME="longhorn-verify-pvc"
POD_NAME="storage-checker"
LH_NS="longhorn-system"
PVC_NS="default"

echo "--- 0. Cluster/Longhorn sanity ---"
kubectl get nodes -o wide
kubectl -n "$LH_NS" get pods | egrep -n 'longhorn-manager|instance-manager|engine-image|longhorn-csi-plugin|csi-provisioner|csi-attacher' || true

echo "--- Longhorn nodes (nodes.longhorn.io) ---"
kubectl -n "$LH_NS" get nodes.longhorn.io -o wide || true

LH_NODE_COUNT="$(kubectl -n "$LH_NS" get nodes.longhorn.io --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ -z "$LH_NODE_COUNT" ] || [ "$LH_NODE_COUNT" -lt 1 ]; then
  echo "ERROR: Could not determine Longhorn node count."
  exit 1
fi

DESIRED_REPLICAS="$(( LH_NODE_COUNT < 2 ? LH_NODE_COUNT : 2 ))"
LH_NODE_NAME="$(kubectl -n "$LH_NS" get nodes.longhorn.io -o jsonpath='{.items[0].metadata.name}')"

echo "--- Using DESIRED_REPLICAS=$DESIRED_REPLICAS (Longhorn nodes=$LH_NODE_COUNT) ---"
echo "--- Pinning test Pod to Longhorn node: $LH_NODE_NAME ---"

# --------- Replica count setting (safe; settings are mutable) ----------
echo "--- 1. Patch Longhorn setting default-replica-count to $DESIRED_REPLICAS ---"
kubectl -n "$LH_NS" patch settings.longhorn.io default-replica-count \
  --type merge -p "{\"value\":\"$DESIRED_REPLICAS\"}" || true

# --------- StorageClass: create a new one (immutable params) ----------
SC_NAME="longhorn-rep-${DESIRED_REPLICAS}"
echo "--- 2. Create (or recreate) StorageClass $SC_NAME ---"
kubectl delete sc "$SC_NAME" --ignore-not-found=true || true

# NOTE: we keep the same core params shape as the base longhorn SC.
# If your Longhorn requires extra params, we can align later.
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${SC_NAME}
provisioner: driver.longhorn.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "${DESIRED_REPLICAS}"
  staleReplicaTimeout: "30"
  fsType: "ext4"
  dataLocality: "disabled"
  fromBackup: ""
EOF

echo "--- 2b. StorageClasses for reference ---"
kubectl get sc -o wide | sed -n '1,200p' || true

# --------- Cleanup Kubernetes objects ----------
echo "--- 3. Cleanup: delete Pod + PVC (namespaced) ---"
kubectl -n "$PVC_NS" delete pod "$POD_NAME" --ignore-not-found=true || true
kubectl -n "$PVC_NS" delete pvc "$PVC_NAME" --ignore-not-found=true || true
kubectl -n "$PVC_NS" wait --for=delete "pvc/${PVC_NAME}" --timeout=60s || true

# --------- Create PVC ----------
echo "--- 4. Create PVC ---"
cat <<EOF | kubectl apply -n "$PVC_NS" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${SC_NAME}
  resources:
    requests:
      storage: 1Gi
EOF

# --------- Create pod (pinned to a Longhorn node) ----------
echo "--- 5. Deploy Test Pod (pinned) ---"
kubectl -n "$PVC_NS" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  nodeName: ${LH_NODE_NAME}
  containers:
  - name: nginx
    image: nginx:stable
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
EOF

# --------- Wait PVC Bound ----------
echo "--- 6. Wait for PVC Bound ---"
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" -n "$PVC_NS" --timeout=180s
kubectl -n "$PVC_NS" get pvc "$PVC_NAME" -o wide

# Determine Longhorn volume name (= PVC.spec.volumeName / PV name in your output)
VOLUME_NAME="$(kubectl -n "$PVC_NS" get pvc "$PVC_NAME" -o jsonpath='{.spec.volumeName}')"
echo "--- 7. Wait for Longhorn Volume/Replica health (prevents blind hanging) ---"
echo "Detected Longhorn volume name: ${VOLUME_NAME}"

# Helper: print volume+replica state
print_longhorn_state() {
  echo "---- Longhorn Volume describe (${VOLUME_NAME}) ----"
  kubectl -n "$LH_NS" describe "volumes.longhorn.io" "$VOLUME_NAME" || true

  echo "---- Longhorn Replica(s) for ${VOLUME_NAME} ----"
  kubectl -n "$LH_NS" get replicas.longhorn.io -o wide | grep "${VOLUME_NAME}-r-" || true
}

# Poll until volume is healthy or faulted
set +e
for i in {1..30}; do
  VOL_STATE="$(kubectl -n "$LH_NS" get volumes.longhorn.io "$VOLUME_NAME" -o jsonpath='{.status.state}' 2>/dev/null)"
  ROBUSTNESS="$(kubectl -n "$LH_NS" get volumes.longhorn.io "$VOLUME_NAME" -o jsonpath='{.status.robustness}' 2>/dev/null)"
  if [ -n "$VOL_STATE" ]; then
    echo "Longhorn volume state=${VOL_STATE} robustness=${ROBUSTNESS} (try $i/30)"
    if [ "$ROBUSTNESS" = "faulted" ] || [ "$VOL_STATE" = "faulted" ]; then
      echo "ERROR: Longhorn volume/replica is faulted; aborting early."
      print_longhorn_state
      # Also show Longhorn system events (often contains the reason)
      kubectl -n "$LH_NS" get events --sort-by=.lastTimestamp | tail -n 120 || true
      exit 1
    fi
    if [ "$VOL_STATE" = "healthy" ] || [ "$ROBUSTNESS" = "healthy" ] || [ "$ROBUSTNESS" = "robust" ]; then
      break
    fi
  fi
  sleep 6
done
POLL_RC=$?
set -e
if [ "$POLL_RC" -ne 0 ]; then
  echo "ERROR: Longhorn volume health polling failed."
  exit 1
fi
echo "--- Longhorn volume appears healthy enough; proceed to Pod readiness check ---"

# --------- Wait Pod Ready with better debug on failure ----------
echo "--- 8. Wait for Pod Ready (with debug on failure) ---"
set +e
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$PVC_NS" --timeout=240s
POD_RC=$?
set -e

if [ "$POD_RC" -ne 0 ]; then
  echo "ERROR: Pod did NOT become Ready in time."

  echo "---- Pod wide ----"
  kubectl -n "$PVC_NS" get pod "$POD_NAME" -o wide || true

  echo "---- Pod describe (events included) ----"
  kubectl -n "$PVC_NS" describe pod "$POD_NAME" | sed -n '/Events:/,$p' || true

  echo "---- PVC describe ----"
  kubectl -n "$PVC_NS" describe pvc "$PVC_NAME" || true

  print_longhorn_state

  # Correct manager debug: your deployment name differed earlier; so grab the manager pod(s) and tail logs.
  echo "---- Longhorn manager pod logs (tail) ----"
  kubectl -n "$LH_NS" get pods -o name | grep longhorn-manager || true
  kubectl -n "$LH_NS" logs -l app.kubernetes.io/name=longhorn-manager --tail=200 || true
  kubectl -n "$LH_NS" logs deploy/longhorn-manager --tail=200 || true
  kubectl -n "$LH_NS" logs -l app=longhorn-manager --tail=200 || true

  # Also show recent longhorn-system events
  kubectl -n "$LH_NS" get events --sort-by=.lastTimestamp | tail -n 120 || true

  exit 1
fi

echo "--------------------------------------------------------"
echo "Your PVC is BOUND and your Pod is READY."
kubectl -n "$PVC_NS" get pvc "$PVC_NAME" -o wide
kubectl -n "$PVC_NS" get pod "$POD_NAME" -o wide
echo "--------------------------------------------------------"