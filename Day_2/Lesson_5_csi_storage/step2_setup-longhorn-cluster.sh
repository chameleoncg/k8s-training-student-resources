#!/bin/bash

# Exit on any error
set -e

echo "--- 1. Creating KiND Multi-Node Configuration ---"
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
[ -f kind-config.yaml ] && echo "✅ Config file created."

echo "--- 2. Building 3-Node Kubernetes Cluster ---"
kind delete cluster --name longhorn-lab || true
kind create cluster --name longhorn-lab --config kind-config.yaml

# VERIFICATION: Check if nodes are online
echo "Verifying nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s
kubectl get nodes
echo "✅ Cluster nodes are Ready."

echo "--- 3. Installing Host Dependencies ---"
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

# VERIFICATION: Check if iscsid is actually running
systemctl is-active --quiet iscsid && echo "✅ iscsid service is active."

echo "--- 4. Deploying Longhorn CSI (v1.6.0) ---"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

echo "--- 5. Waiting for Longhorn System Pods ---"
# Give the namespace a moment to be created
sleep 5
echo "Waiting for longhorn-manager pods to be ready (this takes ~2 mins)..."
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=180s

# VERIFICATION: List all pods in the namespace
kubectl get pods -n longhorn-system
echo "✅ Longhorn control plane is Running."

echo "--- 6. Configuring Default StorageClass ---"
# We need to wait for the storageclass to actually appear in the API
MAX_RETRIES=10
COUNT=0
while ! kubectl get storageclass longhorn >/dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Error: Longhorn StorageClass never appeared."
        exit 1
    fi
    echo "Waiting for Longhorn StorageClass to be created..."
    sleep 5
    ((COUNT++))
done

# Disable 'standard' and enable 'longhorn'
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# VERIFICATION: Check default status
kubectl get sc
echo "✅ Longhorn is now the default StorageClass."

echo "--------------------------------------------------------"
echo "🚀 ALL VERIFICATIONS PASSED"
echo "Longhorn is ready for Lesson 5 labs."
echo "--------------------------------------------------------"