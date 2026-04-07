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


sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

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

sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        cgroup-driver: cgroupfs
- role: worker
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        cgroup-driver: cgroupfs
  extraMounts:
  - hostPath: /lib/modules
    containerPath: /lib/modules
    readOnly: true
  - hostPath: /run/iscsid
    containerPath: /run/iscsid
  - hostPath: /var/lib/iscsi
    containerPath: /var/lib/iscsi
  - hostPath: /dev
    containerPath: /dev
  - hostPath: /boot
    containerPath: /boot

containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = false
EOF

sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

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

sudo systemctl stop iscsid.socket iscsid
sudo systemctl start iscsid.socket iscsid


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
# 3c) Pre-flight: wait for CNI to come up before Longhorn install
# -------------------------
echo "--- 3c. Pre-flight: waiting for networking pods (CNI) ---"

MAX_WAIT=120   # seconds
SLEEP=5
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # kindnet is default; include other possible CNIs
  CNI_PODS="$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
    | grep -Ei 'kindnet|calico|cilium|flannel|kube-router|cni' || true)"

  # If nothing matches, wait a bit more (CNI might not have been created yet)
  if [ -z "$CNI_PODS" ]; then
    echo "No networking pods detected yet... (${ELAPSED}s/$MAX_WAIT)"
    sleep $SLEEP
    ELAPSED=$((ELAPSED + SLEEP))
    continue
  fi

  echo "Detected networking pods:"
  echo "$CNI_PODS"

  # If any are still Pending/CrashLoop/ContainerCreating, wait a little
  if echo "$CNI_PODS" | grep -Ei 'ContainerCreating|CrashLoopBackOff|Pending' >/dev/null; then
    echo "Networking pods not ready yet... waiting (${ELAPSED}s/$MAX_WAIT)"
    sleep $SLEEP
    ELAPSED=$((ELAPSED + SLEEP))
    continue
  fi

  # Looks good
  echo "Networking pods look healthy. Proceeding..."
  break
done

# Final check: if we still don't have networking pods, fail
if [ -z "$CNI_PODS" ]; then
  echo "ERROR: Timed out waiting for networking (CNI) pods."
  exit 1
fi

# Optional: show kube-system pod summary
kubectl get pods -n kube-system


# -------------------------
# 4) Install Longhorn
# -------------------------
echo "--- 4. Deploying Longhorn CSI (v1.6.0) ---"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

echo "--- Patching longhorn-manager to remove --upgrade-version-check ---"

# Compute BOTH container_index and command_index for the exact flag we want removed
PATCH_RESULT="$(
kubectl -n longhorn-system get ds longhorn-manager -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
spec=d["spec"]["template"]["spec"]
cs=spec["containers"]
for ci,c in enumerate(cs):
  if c.get("name")=="longhorn-manager":
    cmd=c.get("command",[]) or []
    for i,a in enumerate(cmd):
      if a=="--upgrade-version-check":
        print(ci, i)
        sys.exit(0)
print("NONE NONE")
'
)"

if echo "$PATCH_RESULT" | grep -q "NONE"; then
  echo "Flag --upgrade-version-check not found; skipping patch."
else
  CONTAINER_INDEX="$(echo "$PATCH_RESULT" | awk '{print $1}')"
  CMD_INDEX="$(echo "$PATCH_RESULT" | awk '{print $2}')"
  echo "Removing --upgrade-version-check at containers/${CONTAINER_INDEX}/command/${CMD_INDEX}"

  kubectl -n longhorn-system patch ds/longhorn-manager --type='json' -p="[
    {\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/${CONTAINER_INDEX}/command/${CMD_INDEX}\"}
  ]" || true

  # Restart once (not twice)
  kubectl -n longhorn-system rollout restart ds/longhorn-manager || true

  # Verification: print manager command args (so you can see the flag is gone)
  echo "--- longhorn-manager command after patch ---"
  kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{range .spec.template.spec.containers[?(@.name=="longhorn-manager")].command[*]}{.}{"\n"}{end}' || true
fi

# Wait for DS rollout to complete before continuing
kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=3m || true

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


# Set default StorageClass annotations.
kubectl patch storageclass standard \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true


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


kubectl get sc
echo "--------------------------------------------------------"
echo "LONGHORN READY"
echo "--------------------------------------------------------"