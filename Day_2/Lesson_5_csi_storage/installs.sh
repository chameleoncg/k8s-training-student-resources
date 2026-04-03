#!/bin/bash

# install Docker Engine
echo "--- Installing Docker ---"
sudo apt update
sudo apt install -y docker.io

#  run docker commands without 'sudo'
echo "--- Configuring Permissions ---"
sudo usermod -aG docker $USER

# install KiND (Kubernetes in Docker)
echo "--- Installing KiND ---"
# Download the specific binary for AMD64 Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# install kubectl (The Remote Control)
echo "--- Installing kubectl ---"
sudo snap install kubectl --classic

# check 
echo "--- Verifying Installations ---"
docker --version
kind --version
kubectl version --client

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "IMPORTANT: You MUST log out and log back in (or run 'newgrp docker')"
echo "to apply the permissions changes"
echo "--------------------------------------------------------"