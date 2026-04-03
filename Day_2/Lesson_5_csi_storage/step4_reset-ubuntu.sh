#!/bin/bash

# Do not exit on error
set +e

echo "--- 1. Tearing down Kubernetes (KiND) ---"
if command -v kind &> /dev/null; then
    kind delete clusters --all || true
    sudo rm -f /usr/local/bin/kind
    echo "KiND clusters and binary removed."
fi

echo "--- 2. Cleaning up kubectl ---"
if command -v kubectl &> /dev/null; then
    # Try snap first, then manual binary
    sudo snap remove kubectl || true
    sudo rm -f /usr/local/bin/kubectl || true
    rm -rf ~/.kube
    echo "kubectl removed and config cleared."
fi

echo "--- 3. Wiping Docker Environment ---"
if command -v docker &> /dev/null; then
    echo "Stopping all containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker system prune -a --volumes -f || true
    
    echo "Uninstalling Docker packages..."
    sudo apt purge -y docker.io docker-doc docker-compose podman-docker containerd runc || true
    sudo apt autoremove -y || true
    sudo rm -rf /var/lib/docker
    sudo rm -rf /etc/docker
    echo "Docker wiped."
fi

echo "--- 4. Removing Longhorn & Storage Dependencies ---"
sudo systemctl stop iscsid || true
sudo apt purge -y open-iscsi nfs-common || true
sudo apt autoremove -y || true
sudo rm -rf /var/lib/longhorn
echo "Storage dependencies removed."

echo "--- 5. Final Filesystem Cleanup ---"
# Remove any leftover YAML configs or local scripts
rm -f kind-config.yaml installs.sh setup-longhorn-cluster.sh verify-longhorn.sh reset-ubuntu.sh
sudo apt clean
echo "Local scripts and cache cleared."

echo "--------------------------------------------------------"
echo "RESETS COMPLETE"
echo "Your Ubuntu VM is back to a (mostly) baseline state."
echo "--------------------------------------------------------"