#!/usr/bin/env bash
# Full reset of Kubernetes + Longhorn lab artifacts (best-effort)
set +e

echo "========================================================"
echo "RESET START - Host: $(hostname) - User: $(whoami)"
echo "========================================================"

# -------------------------
# Helpers
# -------------------------
log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run_ign() { "$@" >/dev/null 2>&1 || true; }

# -------------------------
# 0) If kubectl exists AND kubeconfig exists, delete Longhorn namespace (best-effort)
#    (This is optional and only applies if this node has kubectl configured.)
# -------------------------
if have kubectl && [ -f "$HOME/.kube/config" ]; then
  log "Attempting to delete Longhorn namespace (best-effort)..."
  kubectl delete ns longhorn-system --wait=false --ignore-not-found=true 2>/dev/null || true
  # Also attempt to clean up common resources (best-effort)
  kubectl delete storageclass longhorn --ignore-not-found=true 2>/dev/null || true
  kubectl delete crd volumes.longhorn.io --ignore-not-found=true 2>/dev/null || true
fi

# -------------------------
# 1) Tear down kind clusters (if present)
# -------------------------
log "--- 1. Tearing down Kubernetes (kind) ---"
if have kind; then
  kind delete clusters --all >/dev/null 2>&1 || true
  sudo rm -f /usr/local/bin/kind || true
  # Some distros install kind into /bin; remove if found
  sudo rm -f /bin/kind || true
  log "KiND clusters and binary removed (best-effort)."
fi

# -------------------------
# 2) Remove kubectl/kubeadm/kubelet (if present)
# -------------------------
log "--- 2. Removing kubectl/kubeadm/kubelet tooling (best-effort) ---"
if have kubectl; then
  # snap-based kubectl
  if have snap; then
    snap list kubectl >/dev/null 2>&1 && sudo snap remove kubectl >/dev/null 2>&1 || true
  fi
  sudo rm -f /usr/local/bin/kubectl || true
  sudo rm -f /bin/kubectl || true
fi

# Purge kube packages if installed via apt
run_ign sudo apt-get purge -y kubelet kubeadm kubectl 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# Clean kube configs
rm -rf "$HOME/.kube" 2>/dev/null || true
sudo rm -rf /etc/kubernetes 2>/dev/null || true

# -------------------------
# 3) Stop core services (kubelet/container runtime/iSCSI)
# -------------------------
log "--- 3. Stopping services (best-effort) ---"
sudo systemctl stop kubelet 2>/dev/null || true
sudo systemctl stop docker 2>/dev/null || true
sudo systemctl stop containerd 2>/dev/null || true
sudo systemctl stop iscsid 2>/dev/null || true

# If kubelet uses drop-ins, remove them later with directory wipe.

# -------------------------
# 4) Uninstall container runtime + k8s networking bits (best-effort)
# -------------------------
log "--- 4. Purging Docker/containerd and k8s networking packages (best-effort) ---"

# Docker
if have docker || [ -d /var/lib/docker ]; then
  log "Stopping Docker containers (best-effort)..."
  if have docker; then
    docker stop $(docker ps -aq) >/dev/null 2>&1 || true
  fi

  log "Disabling Docker systemd sockets/units (best-effort)..."
  sudo systemctl stop docker.service docker.socket 2>/dev/null || true
  sudo systemctl unmask docker.service docker.socket 2>/dev/null || true

  run_ign sudo apt-get purge -y docker.io docker-doc docker-compose-plugin podman-docker containerd runc
  run_ign sudo apt-get autoremove -y
fi

# containerd / cri-o remnants (even if you already purged docker)
run_ign sudo apt-get purge -y containerd.io cri-tools runc 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# Kubernetes networking (CNI) bits (best-effort)
run_ign sudo apt-get purge -y kubernetes-cni cni-plugin-calico cni-plugin-flannel 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# -------------------------
# 5) iSCSI cleanup (important for Longhorn full removal)
# -------------------------
log "--- 5. iSCSI / storage dependencies cleanup ---"
run_ign sudo apt-get purge -y open-iscsi nfs-common 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# Logout any iSCSI sessions if iscsiadm exists
if have iscsiadm; then
  log "Logging out iSCSI sessions (best-effort)..."
  run_ign sudo iscsiadm -m node --logoutall=all
  run_ign sudo iscsiadm -m session --rescan
fi

# Stop iscsid again (in case it restarted)
sudo systemctl stop iscsid 2>/dev/null || true

# -------------------------
# 6) Longhorn cleanup (node-level disk state)
# -------------------------
log "--- 6. Removing Longhorn state from disk (node-level) ---"
sudo systemctl stop longhorn* 2>/dev/null || true

# Common Longhorn locations
sudo rm -rf /var/lib/longhorn 2>/dev/null || true
sudo rm -rf /etc/longhorn 2>/dev/null || true
sudo rm -rf /etc/longhorn* 2>/dev/null || true

# Sometimes Longhorn leaves files under these dirs via kubelet mounts/plugins
sudo rm -rf /var/lib/kubelet/plugins/kubernetes.io/csi/* 2>/dev/null || true
sudo rm -rf /var/lib/kubelet/device-plugins/* 2>/dev/null || true

# -------------------------
# 7) Kubernetes node state wipe (this is usually what’s missing)
# -------------------------
log "--- 7. Wiping kubelet + CNI + CSI mount state ---"

# CSI/mounts/pod state
sudo rm -rf /var/lib/kubelet 2>/dev/null || true
sudo rm -rf /var/lib/cni 2>/dev/null || true
sudo rm -rf /etc/cni/net.d 2>/dev/null || true

# Pod networking / iptables rules (best-effort)
# WARNING: This affects host networking rules. Since you asked full removal, keep best-effort.
run_ign sudo iptables -t nat -F
run_ign sudo iptables -t nat -X
run_ign sudo iptables -F
run_ign sudo iptables -P FORWARD ACCEPT
run_ign sudo iptables -t mangle -F
run_ign sudo iptables -t raw -F

# If nftables is used, attempt cleanup of generic kube chains (best-effort)
if have nft; then
  run_ign sudo nft flush ruleset
fi

# -------------------------
# 8) Docker filesystem leftovers (if still present)
# -------------------------
log "--- 8. Cleaning Docker filesystem leftovers (best-effort) ---"
sudo rm -rf /var/lib/docker 2>/dev/null || true
sudo rm -rf /etc/docker 2>/dev/null || true
sudo rm -f /var/run/docker.sock 2>/dev/null || true

# -------------------------
# 9) Final filesystem cleanup / apt cache
# -------------------------
log "--- 9. Final cleanup ---"
rm -f kind-config.yaml 2>/dev/null || true
sudo apt clean 2>/dev/null || true
sudo rm -rf /tmp/* 2>/dev/null || true

echo "========================================================"
echo "RESET COMPLETE (best-effort). Host: $(hostname)"
echo "========================================================"