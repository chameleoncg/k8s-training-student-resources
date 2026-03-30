#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)

SIMPLE_CNI_SUFFIX="$1"

for node in $(kubectl get nodes --no-headers |  awk '{print $1}')
do
    docker cp $SCRIPT_DIR/simple-cni."$SIMPLE_CNI_SUFFIX" $node:/opt/cni/bin/simple-cni
    docker cp $SCRIPT_DIR/05-simple-cni.conf $node:/etc/cni/net.d/
    docker cp $SCRIPT_DIR/00-simple-cni.conflist $node:/etc/cni/net.d/
done
