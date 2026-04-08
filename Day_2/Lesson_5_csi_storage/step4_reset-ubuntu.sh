#!/usr/bin/env bash
# Full reset of Kubernetes + Longhorn lab artifacts (no-hang version)
set +e

echo "========================================================"
echo "RESET START - Host: $(hostname) - User: $(whoami)"
echo "========================================================"

# -------------------------
# Helpers
# -------------------------
log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run_ign() { timeout 10s "$@" >/dev/null 2>&1 || true; }

# -------------------------
# 0) Kubernetes Cleanup (Non-blocking)
# -------------------------
if have kubectl && [ -f "$HOME/.kube/config" ]; then
    log "Attempting to delete Longhorn/K8s resources (non-blocking)..."
    # --wait=false is CRITICAL to prevent hanging on stuck Finalizers
    timeout 15s kubectl delete ns longhorn-system --wait=false --ignore-not-found=true 2>/dev/null || true
    timeout 5s kubectl delete storageclass longhorn --ignore-not-found=true 2>/dev/null || true
fi

# -------------------------
# 1) Mount Cleanup (The #1 cause of hangs)
# -------------------------
log "--- 1. Unmounting stale K8s/Longhorn mounts ---"
# Find any kubelet or longhorn mounts and force unmount them lazily (-l)
# This prevents 'rm -rf' from hanging later.
grep -E 'kubelet|longhorn|csi' /proc/mounts | cut -d' ' -f2 | sort -r | while read -r mount_path; do
    log "Unmounting $mount_path..."
    sudo umount -f -l "$mount_path" 2>/dev/null || true
done

# -------------------------
# 2) Tear down kind clusters
# -------------------------
log "--- 2. Tearing down Kubernetes (kind) ---"
if have kind; then
    timeout 30s kind delete clusters --all >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/kind /bin/kind || true
fi

# -------------------------
# 3) Remove Tooling
# -------------------------
log "--- 3. Removing tooling ---"
if have snap; then
    timeout 20s sudo snap remove kubectl 2>/dev/null || true
fi
sudo rm -f /usr/local/bin/kubectl /bin/kubectl || true
run_ign sudo apt-get purge -y kubelet kubeadm kubectl 2>/dev/null

# -------------------------
# 4) Docker/Containerd (With kill protection)
# -------------------------
log "--- 4. Purging Docker/Runtime ---"
if have docker; then
    # Get container IDs first to avoid subshell hangs
    IDS=$(docker ps -aq)
    if [ -n "$IDS" ]; then
        log "Force-killing containers..."
        timeout 15s docker rm -f $IDS >/dev/null 2>&1 || true
    fi
fi

sudo systemctl stop docker.service docker.socket containerd 2>/dev/null || true
run_ign sudo apt-get purge -y docker.io containerd.io runc 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# -------------------------
# 5) iSCSI Cleanup
# -------------------------
log "--- 5. iSCSI cleanup ---"
if have iscsiadm; then
    # logoutall can hang if the target is gone, hence the timeout
    timeout 10s sudo iscsiadm -m node --logoutall=all 2>/dev/null || true
fi
sudo systemctl stop iscsid 2>/dev/null || true
run_ign sudo apt-get purge -y open-iscsi nfs-common 2>/dev/null

# -------------------------
# 6) Deep Filesystem Wipe
# -------------------------
log "--- 6. Wiping all state directories ---"
# We do this AFTER the umount loop above to ensure no hangs
DIRS=(
    "/var/lib/longhorn"
    "/var/lib/kubelet"
    "/var/lib/docker"
    "/var/lib/containerd"
    "/var/lib/cni"
    "/etc/cni"
    "/etc/kubernetes"
    "/etc/longhorn"
    "$HOME/.kube"
)

for dir in "${DIRS[@]}"; do
    log "Removing $dir..."
    sudo rm -rf "$dir" 2>/dev/null || true
done

# -------------------------
# 7) Networking Reset
# -------------------------
log "--- 7. Resetting Firewall/Networking ---"
run_ign sudo iptables -F
run_ign sudo iptables -t nat -F
run_ign sudo iptables -t nat -X
run_ign sudo iptables -P FORWARD ACCEPT

# -------------------------
# 8) Final Cleanup
# -------------------------
log "--- 8. Final APT cleanup ---"
sudo apt-get clean 2>/dev/null || true

echo "========================================================"
echo "RESET COMPLETE. Please reboot to ensure kernel/modules are clean."
echo "========================================================"