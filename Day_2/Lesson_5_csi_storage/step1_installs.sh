#!/bin/bash

# Exit immediately if a command fails
set -e

echo "--- Updating Package Index ---"
sudo apt update

# 1. Ensure curl is installed
echo "--- Checking for curl ---"
sudo apt install -y curl

# 2. Install Docker Engine
echo "--- Installing Docker ---"
sudo apt install -y docker.io
sudo systemctl enable --now docker

# 3. Configure Permissions
echo "--- Configuring Permissions ---"
sudo usermod -aG docker $USER

# 4. Install KiND (Kubernetes in Docker)
echo "--- Installing KiND ---"
# -f makes curl fail if the URL is broken, -L follows redirects
curl -fLo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64

if [ -f "./kind" ]; then
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo "KiND binary moved to /usr/local/bin"
else
    echo "Error: KiND download failed."
    exit 1
fi

# 5. Install kubectl via Snap
echo "--- Installing kubectl ---"
sudo snap install kubectl --classic

# 6. Verify everything
echo "--- Verifying Installations ---"
docker --version
kind version
kubectl version --client


echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "IMPORTANT: You MUST log out and log back in (or run 'newgrp docker')"
echo "to apply the permissions changes"
echo "--------------------------------------------------------"