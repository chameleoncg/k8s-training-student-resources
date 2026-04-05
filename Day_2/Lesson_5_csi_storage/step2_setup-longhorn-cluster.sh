#!/bin/bash
set -e

echo "--- 0. Optimizing Host Resource Limits & Kernel ---"
# This prevents the 'Too many open files' error in KiND/Longhorn
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
# Ensure the kernel allows container networking
sudo sysctl -w net.ipv4.ip_forward=1

# Make it permanent
grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "Host limits and kernel forwarding optimized."

echo "--- 0b. Refreshing Container Runtime ---"
# Force systemd to recognize fresh Docker install/config
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "--- 1. Creating KiND Multi-Node Configuration ---"
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

echo "--- 2. Building 3-Node Kubernetes Cluster ---"
kind delete cluster --name longhorn-lab || true
# Clean up any "dirty" networks left from crashes
docker network prune -f

# Create cluster with an increased internal wait
kind create cluster --name longhorn-lab --config kind-config.yaml --wait 5m

# VERIFICATION: Check if nodes are online (Increased timeout to 300s)
echo "Verifying nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
echo " Cluster nodes are Ready."

echo "--- 3. Installing Host Dependencies ---"
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

# VERIFICATION: Check if iscsid is actually running
systemctl is-active --quiet iscsid && echo " iscsid service is active."

echo "--- 4. Deploying Longhorn CSI (v1.6.0) ---"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

echo "--- 5. Waiting for Longhorn System Pods ---"
sleep 5
echo "Waiting for longhorn-manager pods to be ready (this takes ~2 mins)..."
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=300s

# VERIFICATION: List all pods in the namespace
kubectl get pods -n longhorn-system
echo " Longhorn control plane is Running."

echo "--- 6. Configuring Default StorageClass ---"
MAX_RETRIES=15
COUNT=0
while ! kubectl get storageclass longhorn >/dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "********** Error: Longhorn StorageClass never appeared."
        exit 1
    fi
    echo "Waiting for Longhorn StorageClass to be created... ($COUNT/$MAX_RETRIES)"
    sleep 10
    ((COUNT++))
done

# Disable 'standard' and enable 'longhorn'
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get sc
echo "--------------------------------------------------------"
echo "VERIFICATIONS PASSED - LONGHORN READY"
echo "--------------------------------------------------------"