single-node-kind-cluster:
	kind create cluster --config=single-node-kind-config.yaml --name training
	kubectl apply -f deployment/netshoot.yaml

single-node-kind-no-kubeproxy:
	kind create cluster --config=single-node-kind-config.yaml --name training
	kubectl apply -f deployment/netshoot.yaml

load-simple-cni-1:
	bash simple_cni/load-cni-to-nodes.sh 1

setup-cni-static:
	bash simple_cni/setup-static-node-networking.sh

load-simple-cni-2: setup-cni-static
	bash simple_cni/load-cni-to-nodes.sh 2

cilium-kube-proxy-replacement: single-node-kind-cluster
	helm repo add cilium https://helm.cilium.io/
	helm repo update cilium
	helm upgrade -i cilium cilium/cilium --version 1.19.0 \
		--namespace kube-system \
		--set kubeProxyReplacement=true \
		--set policyEnforcementMode=always \
		--set k8sServiceHost=training-control-plane \
		--set k8sServicePort=6443

load-ebpf-utilities:
	docker exec training-worker apt update
	docker exec training-worker apt install -y bpftool tcpdump iputils-ping

manual-veth-setup: load-ebpf-utilities
	docker exec training-worker ip netns add demo
	docker exec training-worker ip link add demo-host type veth peer name eth0 netns demo
	docker exec training-worker ip link set demo-host up
	docker exec training-worker ip netns exec demo ip link set eth0 up
	docker exec training-worker ip netns exec demo ip addr add 10.41.6.7/16 dev eth0
	docker exec training-worker ip link set demo-host master cni0

clean:
	kind delete cluster --name training ||: