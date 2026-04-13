setup: setup-cluster setup-kyverno

setup-cluster:
	@ registry_up
	@ kind_up

setup-kyverno: setup-cluster
	@ flux install
	@ kubectl apply -f manifests/kyverno-install.yaml
	@ sleep 5

setup-generation-lab: setup-kyverno
	kubectl apply -f manifests/generation-lab/MissionDeployment.yaml
	kubectl apply -f manifests/generation-lab/MissionDeployment-ClusterPolicy.yaml

setup-mutation-lab: setup-kyverno
	kubectl apply -f manifests/mutation-lab/DropAll-Policy.yaml
	kubectl apply -f manifests/mutation-lab/PrivilegeEscalation-Policy.yaml
	kubectl apply -f manifests/mutation-lab/SecComp-Policy.yaml
	kubectl apply -f manifests/mutation-lab/SecurityContext-Policy.yaml
	kubectl apply -f manifests/mutation-lab/CertInjection-Policy.yaml
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ca.key -out ca-certificates.crt -subj "/CN=lab.cluster"
	kubectl create configmap ca-pemstore --from-file ca-certificates.crt

setup-validating-lab: setup-kyverno
	kubectl apply -f manifests/validating-lab/HostMount-Policy.yaml
	kubectl apply -f manifests/validating-lab/HostNamespace-Policy.yaml

teardown:
	kind_down
	registry_down
