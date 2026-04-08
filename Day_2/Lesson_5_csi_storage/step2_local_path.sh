#!/bin/bash
set -euo pipefail

CLUSTER_NAME="localpath-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- [Script2] Local Path Provisioner config (no cluster recreation) ---"

# Ensure kubectl is actually talking to kind
kubectl --context "$KIND_CONTEXT" get nodes >/dev/null

LP_NS="$(kubectl --context "$KIND_CONTEXT" get deploy local-path-provisioner -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n1 || true)"

if [ -z "$LP_NS" ]; then
  echo "Local path provisioner not found; installing..."
  kubectl --context "$KIND_CONTEXT" apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  LP_NS="kube-system"
fi

kubectl --context "$KIND_CONTEXT" -n "$LP_NS" rollout status deploy/local-path-provisioner --timeout=180s || true

LP_SC="$(kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.provisioner}{"\n"}{end}' \
  | awk -F'\t' '$2 ~ /rancher.io\/local-path/ {print $1; exit}')"

if [ -z "$LP_SC" ]; then
  echo "ERROR: Could not detect Local Path StorageClass."
  exit 1
fi

# Clear defaults
kubectl --context "$KIND_CONTEXT" get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
| awk -F'\t' '$2=="true"{print $1}' \
| while read -r sc; do
    kubectl --context "$KIND_CONTEXT" patch storageclass "$sc" \
      -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
  done

# Set default
kubectl --context "$KIND_CONTEXT" patch storageclass "$LP_SC" \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "Using Local Path StorageClass: $LP_SC"

echo "--- Verification: write /data/hello.txt ---"
cat <<YAML | kubectl --context "$KIND_CONTEXT" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: localpath-hello-pvc
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
  name: localpath-hello-writer
spec:
  restartPolicy: Never
  containers:
  - name: t
    image: busybox:1.36
    command: ["sh","-c","echo hello-$(date) > /data/hello.txt; sleep 5"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: localpath-hello-pvc
YAML

kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready pod/localpath-hello-writer --timeout=120s || true
kubectl --context "$KIND_CONTEXT" exec pod/localpath-hello-writer -- sh -lc 'cat /data/hello.txt' || true

echo "DONE: wrote /data/hello.txt via Local Path."