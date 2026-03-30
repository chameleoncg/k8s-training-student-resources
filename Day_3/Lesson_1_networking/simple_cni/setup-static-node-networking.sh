#!/usr/bin/env bash
set -euo pipefail

BRIDGE="${BRIDGE:-cni0}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
GW_IP="${GW_IP:-10.244.0.1}"
GW_PREFIX="${GW_PREFIX:-${POD_CIDR#*/}}" # trims off the CIDR portion

for node in $(kubectl get nodes --no-headers | awk '{print $1}'); do
  docker exec "$node" bash -lc "
    set -euo pipefail

    ip link add '$BRIDGE' type bridge 2>/dev/null ||:
    ip link set '$BRIDGE' up

    ip addr show '$BRIDGE' | grep -qw '$GW_IP' || \
      ip addr add '$GW_IP/$GW_PREFIX' dev '$BRIDGE'

    modprobe br_netfilter 2>/dev/null || true
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null

    iptables -C FORWARD -i '$BRIDGE' -j ACCEPT 2>/dev/null || \
      iptables -A FORWARD -i '$BRIDGE' -j ACCEPT

    iptables -C FORWARD -o '$BRIDGE' -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
      iptables -A FORWARD -o '$BRIDGE' -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    iptables -t nat -C POSTROUTING -s '$POD_CIDR' ! -d '$POD_CIDR' ! -o '$BRIDGE' -j MASQUERADE 2>/dev/null || \
      iptables -t nat -A POSTROUTING -s '$POD_CIDR' ! -d '$POD_CIDR' ! -o '$BRIDGE' -j MASQUERADE
  "
done
