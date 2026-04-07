# Cluster Networking Lab

## Demystifying CNI

Create a cluster and observe the pod and service CIDRs.

```bash
make clean single-node-kind-cluster
cat single-node-kind-config.yaml
```

Load our custom CNI into the cluster and observe what kubelet/CRI provide as parameters.

```bash
kubectl get pods
make load-simple-cni-1
docker exec training-worker tail -f /tmp/cni_log
```

Execute the CNI "install" to create the node bridge that pods will attach to.

```bash
make setup-cni-static
```

Manually create a veth setup that will mimic a CNI pod plugin to understand it manually first.

```bash
ip netns add demo   # Create a network namespace ourselves
ip link add demo-host type veth peer name eth0 netns demo # Create an interface(s)
ip link set demo-host up # Bring up the interfaces
ip netns exec demo ip link set eth0 up
ip netns exec demo ip addr add 10.41.6.7/16 dev eth0
ip link set demo-host master cni0   # Add the interface to the bridge
ping 10.41.6.7
ip netns exec demo ethtool -S eth0 | grep peer # Inspect
ip link del demo-host && ip netns del demo # Cleanup
```

Now load our custom CNI that performs this logic per pod created. This script will return the required JSON from the CNI plugin.

```bash
make load-simple-cni-2
kubectl get pods # Observe running state and pod CIDR assigned
docker exec training-worker ip link
curl http://{worker IP}:30080
```

## Kubeproxy

Acknowledge that the above curl is operated on through a node port service layer. The expectation might be a port bound to the host, but its actually iptable results created by kube-proxy.

```bash
ss -nato | grep 30080 # note that no port is bound
iptables-save | grep 30080
iptables-save | grep {slug}
iptables-save | grep {SEP slug}
kubectl get endpointslice
```

## eBPF

Observe our contrived ebpf program that will just redirect from a fake "endpointslice" and reroute it to our backend pod.

```bash
cd lb_prog
make all
curl http://{worker IP}:30081 # this is the port that trigger the ebpf redirect
```

Extra credit for C programmers: modify the program to do load balancing to multiple replicas.

## Cilium

Start a cilium cluster and list out BPF maps that are passed from user space to the kernel programs

```bash
make clean cilium-kube-proxy-replacement
cilium bpf endpoint list
cilium bpf lb list
cilium bpf policy list
cilium service list
cilium endpoint list
```