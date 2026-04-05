#!/bin/bash
set -euo pipefail

echo "--- 0. Optimizing Host Resource Limits & Kernel ---"
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
sudo sysctl -w net.ipv4.ip_forward=1

grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "Host limits and kernel forwarding optimized."

echo "--- 0b. Refreshing Container Runtime ---"
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "--- 1. Creating KiND 2-Node Configuration (1 control-plane, 1 worker) ---"
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

echo "--- 2. Building 2-Node Kubernetes Cluster ---"
kind delete cluster --name longhorn-lab || true
docker network prune -f || true

kind create cluster --name longhorn-lab --config kind-config.yaml --wait 5m

echo "--- Verification: Check if nodes are online ---"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
echo "Cluster nodes are Ready."

echo "--- 3. Installing Host Dependencies (VM host) ---"
sudo apt update
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid || true

echo "--- 3b. Install open-iscsi inside kind node containers (CRITICAL for Longhorn iSCSI frontend) ---"
# List kind node containers for cluster "longhorn-lab"
KIND_NODE_CONTAINERS="$(docker ps --filter label=io.x-k8s.kind.cluster=longhorn-lab --format '{{.Names}}')"

if [ -z "$KIND_NODE_CONTAINERS" ]; then
  echo "WARNING: Could not detect kind node containers via labels."
  echo "Run: docker ps | grep kindest/node (manual verification needed)."
else
  for c in $KIND_NODE_CONTAINERS; do
    echo "==> Configuring open-iscsi in kind node container: $c"

    # Install open-iscsi tools (kind node images are usually Debian/Ubuntu based)
    docker exec "$c" sh -c "apt-get update && apt-get install -y open-iscsi" || true

    # Ensure initiatorname exists (Longhorn engine expects initiatorname for iscsid/iscsiadm flows)
    docker exec "$c" sh -c 'if [ ! -s /etc/iscsi/initiatorname.iscsi ]; then echo "InitiatorName=iqn.2026-04.com.longhorn:$(hostname)" > /etc/iscsi/initiatorname.iscsi; fi' || true

    # Start iscsid (best-effort: container may not have systemd)
    docker exec "$c" sh -c 'pkill iscsid 2>/dev/null || true; (iscsid || true) && (pgrep -a iscsid || true)' || true
  done
fi

echo "--- Verification: iscsid running? ---"
systemctl is-active --quiet iscsid && echo " iscsid service is active."

echo "--- 4. Deploying Longhorn CSI (v1.6.0) ---"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

echo "--- 5. Waiting for Longhorn system components (defensive) ---"

wait_longhorn() {
  local ns="longhorn-system"
  local attempt=1
  local max_attempts=4

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "Attempt $attempt/$max_attempts: checking Longhorn pods readiness..."

    # Quick snapshot (always useful)
    kubectl get pods -n "$ns" -o wide || true

    # If any manager-like pods exist, wait for at least one pod to be Ready.
    # (Avoids fragile field-selector logic.)
    if kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | grep -qi "longhorn.*manager"; then
      kubectl wait -n "$ns" --for=condition=Ready pod --timeout=90s 2>/dev/null || true
    fi

    # Prefer controller readiness when possible
    if kubectl -n "$ns" get deploy --no-headers 2>/dev/null | grep -qi manager; then
      kubectl -n "$ns" get deploy --no-headers -o name 2>/dev/null \
        | grep -i manager | head -n1 \
        | xargs -r -I{} kubectl -n "$ns" rollout status {} --timeout=90s || true
      # If rollout status succeeded, controllers should be mostly healthy.
      # We return early only if at least one pod is Ready.
      if kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '{print $2}' | grep -qE 'Running|READY'; then
        return 0
      fi
    fi

    # If we get here, dump + restart best-effort and retry.
    echo "Longhorn not ready yet; dumping diagnostics and restarting best-effort controllers..."
    kubectl -n "$ns" get pods -o wide || true
    kubectl -n "$ns" get events --sort-by=.metadata.creationTimestamp | tail -n 30 || true

    # Restart best-effort: deployments and daemons that look like Longhorn components
    kubectl -n "$ns" get deploy --no-headers -o name 2>/dev/null \
      | grep -Ei 'longhorn|manager|csi|ui' \
      | while read -r d; do
          kubectl -n "$ns" rollout restart "$d" || true
        done

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

kubectl get pods -n longhorn-system
echo "Longhorn control plane is Running (or at least controllers have reached readiness)."

echo "--- 6. Configuring Default StorageClass ---"
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

kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
kubectl patch storageclass longhorn  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

kubectl get sc
echo "--------------------------------------------------------"
echo "LONGHORN READY"
echo "--------------------------------------------------------"