SHELL := /bin/bash

CLUSTER_NAME ?= training
KUBECTL ?= kubectl --context kind-$(CLUSTER_NAME)
KIND ?= kind
HELM ?= helm
DOCKER ?= docker

DEPLOY_DIR := deploy
APP_IMAGE := debugging/distroless-python:1.0.0
KIND_CONFIG := single-node-kind-config.yaml

.PHONY: all single-node-kind-cluster namespace load-kyverno build-app-image \
	load-app-image create-private-registry-secret deploy validate clean

all: deploy

single-node-kind-cluster:
	@if $(KIND) get clusters | grep -qx '$(CLUSTER_NAME)'; then \
		echo "kind cluster $(CLUSTER_NAME) already exists"; \
	else \
		$(KIND) create cluster --config=$(KIND_CONFIG) --name $(CLUSTER_NAME); \
	fi

namespace: single-node-kind-cluster
	$(KUBECTL) apply -f $(DEPLOY_DIR)/namespace.yaml

load-kyverno: single-node-kind-cluster
	$(HELM) repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
	$(HELM) repo update kyverno
	$(HELM) upgrade -i kyverno kyverno/kyverno \
		--namespace kyverno \
		--create-namespace
	$(KUBECTL) rollout status deployment/kyverno-admission-controller -n kyverno --timeout=10m
	$(KUBECTL) rollout status deployment/kyverno-background-controller -n kyverno --timeout=10m
	$(KUBECTL) rollout status deployment/kyverno-cleanup-controller -n kyverno --timeout=10m
	$(KUBECTL) rollout status deployment/kyverno-reports-controller -n kyverno --timeout=10m

build-app-image:
	$(DOCKER) build -t $(APP_IMAGE) .

load-app-image: single-node-kind-cluster build-app-image
	$(KIND) load docker-image --name $(CLUSTER_NAME) $(APP_IMAGE)

create-private-registry-secret: namespace
	$(KUBECTL) create secret docker-registry private-registry-creds \
		--namespace debugging \
		--docker-server ghcr.io \
		--docker-username training \
		--docker-password training \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -

deploy: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/kyverno-policy.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/deployment1.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/deployment2.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/deployment3.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/deployment4.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/deployment5.yaml

validate:
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/namespace.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/deployment1.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/deployment2.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/deployment3.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/deployment4.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/deployment5.yaml

clean:
	$(KIND) delete cluster --name $(CLUSTER_NAME) || :
