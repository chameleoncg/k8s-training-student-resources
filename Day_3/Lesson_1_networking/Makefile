single-node-kind-cluster:
	kind create cluster --config=single-node-kind-config.yaml --name training
	kubectl apply -f deployment/netshoot.yaml

single-node-kind-no-kubeproxy:
	kind create cluster --config=single-node-kind-config.yaml --name training
	kubectl apply -f deployment/netshoot.yaml

load-simple-ci-1:
	bash simple_cni/load-cni-to-nodes.sh 1

setup-cni-static:
	bash simple_cni/setup-static-node-networking.sh

load-simple-ci-2: setup-cni-static
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
	docker exec $(WORKER) apt update
	docker exec $(WORKER) apt install -y bpftool tcpdump

clean:
	kind delete cluster --name training ||: