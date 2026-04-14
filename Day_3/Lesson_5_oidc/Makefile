.PHONY: cluster gateway-api-crds cilium namespace deploy-base deploy configure-client deploy-app relax-http-realms status validate urls clean

NAMESPACE ?= oidc
REALM ?= training
UPSTREAM_REALM ?= upstream
CLIENT_ID ?= training-app
CLIENT_SECRET ?=
PUBLIC_IP ?= 127.0.0.1
PORT ?= 8080
CILIUM_VERSION ?= 1.19.2
GATEWAY_API_VERSION ?= v1.2.0
GATEWAY_API_MANIFEST ?= https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml
BROKER_ALIAS ?= upstream-saml

KEYCLOAK_HOST ?= keycloak.$(PUBLIC_IP).nip.io
UPSTREAM_KEYCLOAK_HOST ?= upstream.$(PUBLIC_IP).nip.io
APP_HOST ?= app.$(PUBLIC_IP).nip.io

KEYCLOAK_URL ?= http://$(KEYCLOAK_HOST):$(PORT)
UPSTREAM_KEYCLOAK_URL ?= http://$(UPSTREAM_KEYCLOAK_HOST):$(PORT)
APP_URL ?= http://$(APP_HOST):$(PORT)
REDIRECT_URI ?= $(APP_URL)/oauth2/callback
POST_LOGOUT_REDIRECT_URI ?= $(APP_URL)/*
UPSTREAM_SAML_METADATA_URL ?= $(UPSTREAM_KEYCLOAK_URL)/realms/$(UPSTREAM_REALM)/protocol/saml/descriptor
BROKER_SP_METADATA_URL ?= $(KEYCLOAK_URL)/realms/$(REALM)/broker/$(BROKER_ALIAS)/endpoint/descriptor
RENDER_ENV = KEYCLOAK_HOST='$(KEYCLOAK_HOST)' UPSTREAM_KEYCLOAK_HOST='$(UPSTREAM_KEYCLOAK_HOST)' APP_HOST='$(APP_HOST)' PORT='$(PORT)' KEYCLOAK_URL='$(KEYCLOAK_URL)' UPSTREAM_KEYCLOAK_URL='$(UPSTREAM_KEYCLOAK_URL)' APP_URL='$(APP_URL)' REDIRECT_URI='$(REDIRECT_URI)' POST_LOGOUT_REDIRECT_URI='$(POST_LOGOUT_REDIRECT_URI)' BROKER_ALIAS='$(BROKER_ALIAS)'

# create the cluster, run `make clean cluster` to recreate it
cluster:
	kind create cluster --config kind-config.yaml --name training

gateway-api-crds:
	kubectl apply --server-side -f $(GATEWAY_API_MANIFEST)

cilium: gateway-api-crds
	helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
	helm repo update cilium
	helm upgrade -i cilium cilium/cilium --version $(CILIUM_VERSION) \
		--namespace kube-system \
		--set kubeProxyReplacement=true \
		--set gatewayAPI.enabled=true \
		--set gatewayAPI.hostNetwork.enabled=true \
		--set envoy.enabled=true \
		--set operator.replicas=1 \
		--set k8sServiceHost=training-control-plane \
		--set k8sServicePort=6443
	kubectl rollout status daemonset/cilium -n kube-system --timeout=300s
	kubectl rollout status deployment/cilium-operator -n kube-system --timeout=300s
	kubectl rollout status daemonset/cilium-envoy -n kube-system --timeout=300s
	kubectl wait --for=condition=Ready nodes --all --timeout=300s

namespace:
	kubectl apply -f deployment/namespace.yaml

deploy-base: namespace
	$(RENDER_ENV) envsubst < deployment/keycloak.yaml | kubectl apply -f -
	kubectl apply -f deployment/echo-app.yaml
	$(RENDER_ENV) envsubst < deployment/gateway.yaml | kubectl apply -f -
	kubectl rollout status deployment/keycloak -n $(NAMESPACE) --timeout=300s
	kubectl rollout status deployment/upstream-keycloak -n $(NAMESPACE) --timeout=300s
	$(MAKE) relax-http-realms
	kubectl rollout status deployment/oidc-echo -n $(NAMESPACE) --timeout=180s
	kubectl wait -n $(NAMESPACE) --for=condition=Accepted=true gateway/oidc-gateway --timeout=180s
	kubectl wait -n $(NAMESPACE) \
		--for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
		httproute/keycloak-route \
		--timeout=180s
	kubectl wait -n $(NAMESPACE) \
		--for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
		httproute/upstream-keycloak-route \
		--timeout=180s

deploy: cluster cilium deploy-base

configure-client:
	@test -n "$(CLIENT_SECRET)" || (echo "Set CLIENT_SECRET when running this target." && exit 1)
	kubectl -n $(NAMESPACE) create secret generic oauth2-proxy-secrets \
		--from-literal=client-id="$(CLIENT_ID)" \
		--from-literal=client-secret="$(CLIENT_SECRET)" \
		--from-literal=cookie-secret="$$(openssl rand -hex 16)" \
		--dry-run=client -o yaml | kubectl apply -f -
	@if kubectl get deployment/oauth2-proxy -n $(NAMESPACE) >/dev/null 2>&1; then \
		kubectl rollout restart deployment/oauth2-proxy -n $(NAMESPACE); \
	fi

deploy-app:
	$(RENDER_ENV) envsubst < deployment/oauth2-proxy.yaml | kubectl apply -f -
	kubectl rollout status deployment/oauth2-proxy -n $(NAMESPACE) --timeout=180s
	kubectl wait -n $(NAMESPACE) \
		--for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
		httproute/app-route \
		--timeout=180s

relax-http-realms:
	kubectl exec -n $(NAMESPACE) deploy/keycloak -- \
		/opt/keycloak/bin/kcadm.sh config credentials \
		--server http://localhost:$(PORT) \
		--realm master \
		--user admin \
		--password admin123admin >/dev/null
	kubectl exec -n $(NAMESPACE) deploy/keycloak -- \
		/opt/keycloak/bin/kcadm.sh update realms/master \
		-s sslRequired=NONE >/dev/null
	kubectl exec -n $(NAMESPACE) deploy/keycloak -- \
		/opt/keycloak/bin/kcadm.sh update realms/$(REALM) \
		-s sslRequired=NONE >/dev/null
	kubectl exec -n $(NAMESPACE) deploy/upstream-keycloak -- \
		/opt/keycloak/bin/kcadm.sh config credentials \
		--server http://localhost:$(PORT) \
		--realm master \
		--user admin \
		--password admin123admin >/dev/null
	kubectl exec -n $(NAMESPACE) deploy/upstream-keycloak -- \
		/opt/keycloak/bin/kcadm.sh update realms/master \
		-s sslRequired=NONE >/dev/null
	kubectl exec -n $(NAMESPACE) deploy/upstream-keycloak -- \
		/opt/keycloak/bin/kcadm.sh update realms/$(UPSTREAM_REALM) \
		-s sslRequired=NONE >/dev/null

urls:
	@echo "APP_URL=$(APP_URL)"
	@echo "BROKER_ALIAS=$(BROKER_ALIAS)"
	@echo "KEYCLOAK_URL=$(KEYCLOAK_URL)"
	@echo "POST_LOGOUT_REDIRECT_URI=$(POST_LOGOUT_REDIRECT_URI)"
	@echo "PUBLIC_IP=$(PUBLIC_IP)"
	@echo "REDIRECT_URI=$(REDIRECT_URI)"
	@echo "UPSTREAM_KEYCLOAK_URL=$(UPSTREAM_KEYCLOAK_URL)"
	@echo "UPSTREAM_SAML_METADATA_URL=$(UPSTREAM_SAML_METADATA_URL)"
	@echo "BROKER_SP_METADATA_URL=$(BROKER_SP_METADATA_URL)"

clean:
	kind delete cluster --name training || :
