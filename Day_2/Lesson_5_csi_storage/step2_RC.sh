#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"

NS="default"
CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"

SUFFIX="$(date +%s)"
PVC_NAME="rook-ceph-verify-pvc-${SUFFIX}"
POD_NAME="rook-ceph-verify-writer-${SUFFIX}"

echo "--- [Script2] Rook-Ceph Verification (unique per run) ---"

echo "--- 0. Preflight: pool Ready (bounded) ---"
deadline=$((SECONDS+900))
while true; do
  phase="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" = "Ready" ]; then
    echo "replicapool Ready"
    break
  fi
  if [ $SECONDS -gt $deadline ]; then
    echo "ERROR: replicapool not Ready (last phase: ${phase:-<none>})"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephcluster my-cluster -o wide || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephblockpool replicapool || true
    exit 1
  fi
  echo -n "."
  sleep 5
done
echo ""

echo "--- 1. Wait for CSIDriver registration (bounded) ---"
timeout_seconds=600
start_ts=$(date +%s)

until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for CSIDriver: $CSIDRIVER_NAME"
    kubectl --context "$KIND_CONTEXT" get csidriver || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide || true
    exit 1
  fi
  echo "Waiting for CSIDriver..."
  sleep 5
done
echo "CSIDriver registered: $CSIDRIVER_NAME"

echo "--- 2. Prefer rbd-nbd StorageClass ---"
if kubectl --context "$KIND_CONTEXT" get sc rook-ceph-block-nbd >/dev/null 2>&1; then
  RC_SC="rook-ceph-block-nbd"
else
  RC_SC="rook-ceph-block"
fi

echo "Using StorageClass: $RC_SC"

echo "--- 3. Ensure node-side CSI is healthy (restart if needed) ---"
# If the daemon pod isn't Ready, restarting the daemon pod helps it re-register.
# (This addresses the "node plugin CrashLoopBackOff blocks mounts" learning.)
rbdpods_ready="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -l app=csi-rbdplugin \
  -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.status.containerStatuses[*].ready}{" "}{end}' 2>/dev/null || true)"

# Just check readiness in a simple way:
if kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -l app=csi-rbdplugin | grep -q 'CrashLoopBackOff'; then
  echo "Detected csi-rbdplugin crashloop; restarting..."
  kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" delete pod -l app=csi-rbdplugin --force || true
fi

echo "--- 3.1 Wait for at least one csi-rbdplugin pod to be Ready (bounded) ---"
timeout=300
end_ts=$((SECONDS+timeout))
while true; do
  ready_count="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -l app=csi-rbdplugin \
    -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c 'true' || true)"
  # If the daemon isn't perfectly ordered, we still accept "some" readiness.
  if [ "${ready_count:-0}" -ge 1 ]; then
    echo "csi-rbdplugin appears ready (ready_count=${ready_count})."
    break
  fi

  if [ $SECONDS -gt $end_ts ]; then
    echo "ERROR: timed out waiting for csi-rbdplugin readiness."
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide -l app=csi-rbdplugin || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" logs -l app=csi-rbdplugin --tail=80 || true
    exit 1
  fi

  sleep 5
done

echo "--- 4. Cleanup old resources (safe) ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true

echo "--- 5. Create PVC + verification Pod ---"
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

echo "--- 6. Wait for PVC Bound (bounded) ---"
pvc_phase="$(kubectl --context "$KIND_CONTEXT" -n "$NS" get pvc "$PVC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [ "$pvc_phase" = "Bound" ]; then
  echo "PVC already Bound; continuing."
else
  if ! kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=30m; then
    echo "ERROR: PVC did not bind. Diagnostics:"
    kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
    kubectl --context "$KIND_CONTEXT" -n "$NS" get events --sort-by=.metadata.creationTimestamp | tail -n 200 || true
    exit 1
  fi
fi

echo "--- 7. Wait for Pod Ready ---"
if ! kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=10m; then
  echo "ERROR: Pod not Ready. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pod/"$POD_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide -l app=csi-rbdplugin || true
  # dump CSI node plugin logs from whichever pod exists now
  csi_pod="$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -l app=csi-rbdplugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -n "${csi_pod}" ]; then
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" logs "$csi_pod" --tail=120 || true
  fi
  kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get events --sort-by=.metadata.creationTimestamp | tail -n 200 || true
  exit 1
fi

echo "--- 8. Read evidence file back ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"