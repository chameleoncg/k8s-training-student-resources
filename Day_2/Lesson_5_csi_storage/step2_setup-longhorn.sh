#!/bin/bash
# Step 2: Create a kind cluster and install Longhorn
#
# What this script does (high-level):
#  1) Tunes host kernel limits (inotify, ip_forward)
#  2) Creates a 2-node kind cluster (1 control-plane, 1 worker)
#  3) Installs iSCSI tooling on the host (open-iscsi, nfs-common)
#  4) Installs iSCSI tooling INSIDE the kind node containers as well
#     (Longhorn's engine relies on node namespace iSCSI behavior)
#  5) Installs Longhorn v1.6.0 and waits a bit
#  6) Sets Longhorn StorageClass as the default

set -euo pipefail

# -------------------------
# 0) Host kernel / limits
# -------------------------
echo "--- 0. Optimizing Host Resource Limits & Kernel ---"

# These reduce common lab issues (watch limits and forwarding).
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
sudo sysctl -w net.ipv4.ip_forward=1

# Persist settings across reboots.
grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "Host limits and kernel forwarding optimized."

# -------------------------
# 0b) Restart container runtime (best-effort)
# -------------------------
echo "--- 0b. Refreshing Container Runtime ---"
sudo systemctl daemon-reload
sudo systemctl restart docker

# -------------------------
# 1) kind cluster config
# -------------------------
echo "--- 1. Creating KiND 2-Node Configuration (1 control-plane, 1 worker) ---"
# Note: This file is consumed by kind when creating the cluster.
# It is written dynamically so the script is portable.
cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker

# IMPORTANT:
# Disables systemd cgroups inside kind nodes to avoid certain OCI/cgroup failures.
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = false
EOF

# -------------------------
# 2) Create the kind cluster
# -------------------------
echo "--- 2. Building 2-Node Kubernetes Cluster ---"

# Start from a clean slate each run.
kind delete cluster --name longhorn-lab || true
docker network prune -f || true

# Create a cluster using the above config.
kind create cluster --name longhorn-lab --config kind-config.yaml --wait 15m


# Wait for Kubernetes nodes to be Ready.
echo "--- Verification: Check if nodes are online ---"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
echo "Cluster nodes are Ready."

# -------------------------
# 3) Host dependencies
# -------------------------
# Longhorn's default blockdev frontend uses iSCSI, so we install open-iscsi on the VM host.
echo "--- 3. Installing Host Dependencies (VM host) ---"
sudo apt update
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid || true

# -------------------------
# 3b) iSCSI initiator inside kind nodes
# -------------------------
echo "--- 3b. Install + start iSCSI initiator in kind node containers (FIX for Longhorn) ---"

# kind nodes are Docker containers; Longhorn/instance-manager uses nsenter,
# so iSCSI tools must exist *inside the node containers* too.
KIND_NODE_CONTAINERS="$(docker ps --filter label=io.x-k8s.kind.cluster=longhorn-lab --format '{{.Names}}')"
if [ -z "$KIND_NODE_CONTAINERS" ]; then
  echo "ERROR: Could not detect kind node containers for cluster longhorn-lab."
  exit 1
fi

for c in $KIND_NODE_CONTAINERS; do
  echo "==> Configuring inside kind node container: $c"

  docker exec "$c" sh -c '
    set -e

    # Install required packages in the node container.
    # dbus helps avoid "Failed to connect to bus" problems.
    apt-get update
    apt-get install -y open-iscsi dbus >/dev/null 2>&1 || true

    # Longhorn often expects initiatorname to exist.
    mkdir -p /etc/iscsi
    if [ ! -s /etc/iscsi/initiatorname.iscsi ]; then
      echo "InitiatorName=iqn.2026-04.com.longhorn:$(hostname)" > /etc/iscsi/initiatorname.iscsi
    fi

    # Start dbus (kind containers usually don’t run systemd).
    pkill dbus-daemon >/dev/null 2>&1 || true
    mkdir -p /run/dbus
    dbus-daemon --system --fork || true
    sleep 0.5

    # Start/Restart iscsid and ensure socket directories exist.
    pkill iscsid >/dev/null 2>&1 || true
    mkdir -p /run/iscsid /var/run/iscsid || true

    # Start iscsid in background mode.
    (iscsid -f >/tmp/iscsid.log 2>&1 &) || true
    sleep 1

    # Basic checks (best-effort).
    echo "---- checks ----"
    pgrep -a iscsid || true

    echo "iscsid sockets:"
    ls -la /run/iscsid /var/run/iscsid 2>/dev/null || true

    echo "iscsid unix sockets (ss):"
    ss -xl 2>/dev/null | grep -i iscsid || true

    echo "iscsiadm sanity (should NOT say can not connect to iscsid):"
    iscsiadm -m node -o show 2>&1 | tail -n 10 || true
  ' || true
done

# Host-side confirmation (best-effort)
echo "--- Verification: iscsid running? ---"
systemctl is-active --quiet iscsid && echo " iscsid service is active."

# -------------------------
# 4) Install Longhorn
# -------------------------
echo "--- 4. Deploying Longhorn CSI (v1.6.0) ---"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# -------------------------
# 5) Wait for Longhorn control plane (defensive)
# -------------------------
echo "--- 5. Waiting for Longhorn system components (defensive) ---"

# The wait logic is intentionally “defensive” for lab stability:
# it snapshots pod status and attempts restarts if things appear stuck.
wait_longhorn() {
  local ns="longhorn-system"
  local attempt=1
  local max_attempts=4

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "Attempt $attempt/$max_attempts: checking Longhorn pods readiness..."

    kubectl get pods -n "$ns" -o wide || true

    # If manager-like pods exist, try waiting for them to become Ready.
    if kubectl get pods -n "$ns" --no-headers 2>/dev/null \
      | awk '{print $1}' | grep -qi "longhorn.*manager"; then
      kubectl wait -n "$ns" --for=condition=Ready pod --timeout=90s 2>/dev/null || true
    fi

    # Prefer waiting on deployments whose names contain "manager".
    if kubectl -n "$ns" get deploy --no-headers 2>/dev/null | grep -qi manager; then
      kubectl -n "$ns" get deploy --no-headers -o name 2>/dev/null \
        | grep -i manager | head -n1 \
        | xargs -r -I{} kubectl -n "$ns" rollout status {} --timeout=90s || true

      # If pods show Running/Ready states, treat control plane as “good enough”.
      if kubectl -n "$ns" get pods --no-headers 2>/dev/null \
        | awk '{print $2}' | grep -qE 'Running|READY'; then
        return 0
      fi
    fi

    # If not ready yet: dump diagnostics and restart best-effort components.
    echo "Longhorn not ready yet; dumping diagnostics and restarting best-effort controllers..."
    kubectl -n "$ns" get pods -o wide || true
    kubectl -n "$ns" get events --sort-by=.metadata.creationTimestamp | tail -n 30 || true

    # Restart deployments that look Longhorn-related.
    kubectl -n "$ns" get deploy --no-headers -o name 2>/dev/null \
      | grep -Ei 'longhorn|manager|csi|ui' \
      | while read -r d; do
          kubectl -n "$ns" rollout restart "$d" || true
        done

    # Restart CSI-related daemonsets too.
    kubectl -n "$ns" get ds --no-headers -o name 2>/dev/null \
      | grep -Ei 'csi|node|plugin' \
      | while read -r ds; do
          kubectl -n "$ns" rollout restart "$ds" || true
        done

    attempt=$((attempt + 1))
  done

  echo "ERROR: Longhorn components did not become ready after retries."
  kubectl -n longhorn-system get pods -o wide || true
  kubectl -n longhorn-system get events --sort-by=.metadata.creationTimestamp | tail -n 80 || true
  return 1
}

wait_longhorn

# -------------------------
# Print current pod snapshot
# -------------------------
kubectl get pods -n longhorn-system
echo "Longhorn control plane is Running (or at least controllers have reached readiness)."

# -------------------------
# 6) Configure default StorageClass
# -------------------------
echo "--- 6. Configuring Default StorageClass ---"

# Wait for the longhorn StorageClass to appear.
MAX_RETRIES=15
COUNT=0
while ! kubectl get storageclass longhorn >/dev/null 2>&1; do
  if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
    echo "********** Error: Longhorn StorageClass never appeared."
    exit 1
  fi
  echo "Waiting for Longhorn StorageClass to be created... ($COUNT/$MAX_RETRIES)"
  sleep 10
  COUNT=$((COUNT + 1))
done

# Set default StorageClass annotations.
kubectl patch storageclass standard \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

kubectl get sc
echo "--------------------------------------------------------"
echo "LONGHORN READY"
echo "--------------------------------------------------------"