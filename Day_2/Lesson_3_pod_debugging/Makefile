SHELL := /bin/bash

CLUSTER_NAME ?= training
KUBECTL ?= kubectl --context kind-$(CLUSTER_NAME)
KIND ?= kind
HELM ?= helm
DOCKER ?= docker

DEPLOY_DIR := deploy
LAB6_IMAGE := debugging/lab6-python:1.0.0
LAB4_IMAGE := debugging/distro-python:1.0.0
LAB9_IMAGE := debugging/distroless-python:1.0.0
KIND_CONFIG := single-node-kind-config.yaml

.DEFAULT_GOAL := help

.PHONY: help single-node-kind-cluster namespace load-kyverno build-app-image \
	load-app-image create-private-registry-secret validate clean \
	deploy-lab1 clean-lab1 deploy-lab2 clean-lab2 deploy-lab3 clean-lab3 \
	deploy-lab4 clean-lab4 deploy-labs clean-labs

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
	$(DOCKER) build -t $(LAB4_IMAGE) $(DEPLOY_DIR)/lab2/build/deployment4
	$(DOCKER) build -t $(LAB6_IMAGE) $(DEPLOY_DIR)/lab2/build/deployment6
	$(DOCKER) build -t $(LAB9_IMAGE) $(DEPLOY_DIR)/lab4

load-app-image: single-node-kind-cluster build-app-image
	$(KIND) load docker-image --name $(CLUSTER_NAME) $(LAB4_IMAGE)
	$(KIND) load docker-image --name $(CLUSTER_NAME) $(LAB6_IMAGE)
	$(KIND) load docker-image --name $(CLUSTER_NAME) $(LAB9_IMAGE)

create-private-registry-secret: namespace
	$(KUBECTL) create secret docker-registry private-registry-creds \
		--namespace debugging \
		--docker-server ghcr.io \
		--docker-username training \
		--docker-password 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 \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -

deploy-lab1: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/kyverno-policy.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment1.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment2.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment3.yaml

clean-lab1:
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab1/kyverno-policy.yaml
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab1/deployment1.yaml
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab1/deployment2.yaml
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab1/deployment3.yaml

deploy-lab2: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment4.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment5.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment6.yaml

clean-lab2:
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab2/deployment4.yaml
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab2/deployment5.yaml
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab2/deployment6.yaml

deploy-lab3: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab3/deployment7.yaml
	#$(KUBECTL) apply -f $(DEPLOY_DIR)/lab3/deployment8.yaml

clean-lab3:
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab3/deployment7.yaml
	#$(KUBECTL) delete -f $(DEPLOY_DIR)/lab3/deployment8.yaml

deploy-lab4: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab4/deployment8.yaml

clean-lab4:
	$(KUBECTL) delete -f $(DEPLOY_DIR)/lab4/deployment8.yaml

validate:
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/namespace.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab1/deployment1.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab1/deployment2.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab1/deployment3.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab2/deployment4.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab2/deployment5.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab2/deployment6.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab3/deployment7.yaml
	kubectl apply --dry-run=client -f $(DEPLOY_DIR)/lab3/deployment8.yaml

deploy-labs: namespace create-private-registry-secret load-kyverno load-app-image
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/kyverno-policy.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment1.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment2.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab1/deployment3.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment4.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment5.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab2/deployment6.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab3/deployment7.yaml
	$(KUBECTL) apply -f $(DEPLOY_DIR)/lab4/deployment8.yaml

clean-labs: clean-lab1 clean-lab2 clean-lab3 clean-lab4
	@echo Done

clean:
	$(KIND) delete cluster --name $(CLUSTER_NAME) || :

help:
	@echo "Specify a specific target. deploy-lab<#> or clean perhaps"
