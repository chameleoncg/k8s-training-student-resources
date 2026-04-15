#!/usr/bin/env bash
# Safe reset for kind + rook-ceph lab
set -euo pipefail

echo "========================================================"
echo "RESET START - Host: $(hostname) - User: $(whoami) - PID $$"
echo "========================================================"

# ---- sudo handling: never hang on password prompts ----
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true >/dev/null 2>&1; then
    SUDO="sudo -n"
  else
    echo "ERROR: Need root or passwordless sudo to avoid hanging."
    echo "Run: sudo $0"
    exit 1
  fi
fi

# ---- helpers ----
log() { echo "==> $*"; }
run_ign() { timeout "${2:-10s}" "$1" "${@:3}" >/dev/null 2>&1 || true; }  # not used much
cmd_timeout() { local t="$1"; shift; timeout "$t" "$@" || true; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- 0) Best-effort stop services (no package purges) ----
log "--- 0. Stopping docker/containerd (best-effort) ---"
cmd_timeout 15 $SUDO systemctl stop docker.service docker.socket containerd 2>/dev/null || true

# ---- 1) Unmount stale kubelet/csi/ceph/rbd mounts quickly ----
log "--- 1. Unmounting stale mounts (best-effort, bounded) ---"

UNMOUNT_MAX=50
attempts=0

# Prefer unmounting under common roots
ROOTS=(
  "/var/lib/kubelet"
  "/var/lib/csi"
  "/csi"
  "/var/lib/rook"
  "/var/lib/ceph"
  "/var/run/ceph"
)

# Collect mountpoints under roots
mountpoints="$(
  awk '{
    mp=$2
    # match only if mountpoint begins with one of the roots
    print mp
  }' /proc/mounts 2>/dev/null | head -n 1
)" # placeholder to avoid subshell complexity

# Real collection:
for root in "${ROOTS[@]}"; do
  if [ -d "$root" ]; then
    mps="$(awk -v r="$root" '$2 ~ "^"r {print $2}' /proc/mounts 2>/dev/null | sort -r -u || true)"
    if [ -n "${mps:-}" ]; then
      while IFS= read -r mp; do
        [ -z "$mp" ] && continue
        attempts=$((attempts+1))
        [ "$attempts" -gt "$UNMOUNT_MAX" ] && break
        log "Unmount attempt ($attempts/$UNMOUNT_MAX): $mp"
        cmd_timeout 8 $SUDO umount -f -l "$mp" || true
      done <<< "$mps"
    fi
  fi
done

# ---- 2) Delete rook namespace + any leftover StorageClasses (non-blocking) ----
if have kubectl && [ -f "$HOME/.kube/config" ]; then
  log "--- 2. Deleting rook-ceph namespace and StorageClasses (non-blocking) ---"
  cmd_timeout 25 $SUDO true
  cmd_timeout 25 kubectl delete ns rook-ceph --wait=false --ignore-not-found=true 2>/dev/null || true
  cmd_timeout 15 kubectl delete storageclass rook-ceph-block --ignore-not-found=true 2>/dev/null || true
  cmd_timeout 15 kubectl delete storageclass rook-ceph-block-nbd --ignore-not-found=true 2>/dev/null || true
fi

# ---- 3) Delete kind clusters ----
log "--- 3. Tearing down kind clusters (bounded) ---"
if have kind; then
  cmd_timeout 180 kind delete clusters --all >/dev/null 2>&1 || true
fi

# ---- 4) Kill any remaining kubelet/csi/ceph-related containers (best-effort) ----
if have docker; then
  log "--- 4. Docker cleanup (best-effort, bounded) ---"
  IDS="$(docker ps -aq 2>/dev/null | tr -d '\n' || true)"
  if [ -n "${IDS:-}" ]; then
    # Try a bounded stop/remove
    cmd_timeout 90 docker rm -f $IDS >/dev/null 2>&1 || true
  fi
fi

# ---- 5) Clean filesystem state (bounded deletes) ----
log "--- 5. Removing kubelet/csi/ceph state directories (best-effort, bounded) ---"

DIRS=(
  "/var/lib/csi"
  "/var/lib/rook"
  "/var/lib/ceph"
  "/etc/ceph"
  "/var/log/ceph"
  "/var/run/ceph"
)

for dir in "${DIRS[@]}"; do
  if [ -e "$dir" ]; then
    log "Removing $dir ..."
    cmd_timeout 60 $SUDO rm -rf "$dir" || true
  fi
done

# ---- 6) Optional: detach known loop device image (best-effort) ----
# (Does NOT require apt/dpkg.)
log "--- 6. Loop device cleanup (best-effort) ---"
LOOP_IMG="/tmp/rook-ceph-loop.img"
if [ -f "$LOOP_IMG" ]; then
  # Detach any losetup devices tied to the file (if tool exists)
  if have losetup; then
    loops="$(cmd_timeout 5 $SUDO losetup -j "$LOOP_IMG" 2>/dev/null | awk -F: '{print $1}' | head -n 20 || true)"
    for ld in $loops; do
      log "Detaching loop device $ld"
      cmd_timeout 5 $SUDO losetup -d "$ld" || true
    done
  fi
fi

echo "========================================================"
echo "RESET COMPLETE."
echo "If you still see weird kernel/module behavior, maybe reboot?"
echo "========================================================"