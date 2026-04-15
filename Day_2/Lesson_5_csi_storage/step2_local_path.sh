#!/bin/bash
set -euo pipefail

CLUSTER_NAME="localpath-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- [Script2] Local Path Provisioner config (no cluster recreation) ---"

# Ensure kubectl is actually talking to kind
kubectl --context "$KIND_CONTEXT" get nodes >/dev/null

# Find namespace where local-path-provisioner Deployment exists
LP_DEPLOY_NS="$(kubectl --context "$KIND_CONTEXT" get deploy -A \
  -o jsonpath='{range .items[?(@.metadata.name=="local-path-provisioner")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n1 || true)"

if [ -z "$LP_DEPLOY_NS" ]; then
  echo "Local path provisioner not found; installing..."
  kubectl --context "$KIND_CONTEXT" apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  LP_DEPLOY_NS="kube-system"
fi

kubectl --context "$KIND_CONTEXT" -n "$LP_DEPLOY_NS" rollout status deploy/local-path-provisioner --timeout=180s

# Detect Local Path StorageClass name
LP_SC="$(kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.provisioner}{"\n"}{end}' \
  | awk -F'\t' '$2 ~ /rancher\.io\/local-path/ {print $1; exit}')"

if [ -z "$LP_SC" ]; then
  echo "ERROR: Could not detect Local Path StorageClass."
  exit 1
fi

echo "Using Local Path StorageClass: $LP_SC"

# Set default StorageClass to local-path 
kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
| awk -F'\t' '$2=="true"{print $1}' \
| while read -r sc; do
    [ -n "$sc" ] && kubectl --context "$KIND_CONTEXT" patch storageclass "$sc" \
      -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
  done

kubectl --context "$KIND_CONTEXT" patch storageclass "$LP_SC" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true


PVC_NAME="localpath-hello-pvc"
POD_NAME="localpath-hello-writer"

# Cleanup old resources just in case
kubectl --context "$KIND_CONTEXT" -n default delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n default delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true

echo "--- Verification: write /data/hello.txt using Local Path ---"

cat <<YAML | kubectl --context "$KIND_CONTEXT" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${LP_SC}
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
  - name: t
    image: busybox:1.36
    command:
      - sh
      - -c
      - 'echo localpath-hello-$(date -u) > /data/hello.txt; sleep 20'
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
YAML

kubectl --context "$KIND_CONTEXT" -n default wait --for=condition=Ready pod/"$POD_NAME" --timeout=120s
kubectl --context "$KIND_CONTEXT" -n default exec "$POD_NAME" -- sh -lc 'cat /data/hello.txt'

echo "DONE: wrote /data/hello.txt via Local Path ($LP_SC)."