SHELL := /bin/bash

WORKER ?= training-worker
# Keep in sync with the hardcoded teaching values in load_balancer.c.
VIP_IP ?= 10.41.255.251
DEFAULT_BACKEND_IP ?= 10.41.0.3
WEBSERVER_SELECTOR ?= app=webserver
BPF_PIN_DIR ?= /sys/fs/bpf/lb_prog

.PHONY: build-ebpf load-ebpf-utilities load-ebpf all tail-bfp-logs clean

build-ebpf:
	@BACKEND_IP="$${BACKEND_IP:-$$(kubectl get pod -l $(WEBSERVER_SELECTOR) -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)}"; \
	BACKEND_IP="$${BACKEND_IP:-$(DEFAULT_BACKEND_IP)}"; \
	BACKEND_HEX=$$(printf '0x%02x%02x%02x%02x' $${BACKEND_IP//./ }); \
	echo "Building xdp_lb_kern.o with VIP $(VIP_IP) and backend $$BACKEND_IP"; \
	clang -target bpf \
		-I /usr/include/bpf \
		-D __BPF_TRACING__ \
		-D REAL_BACKEND_RAW_IP=$$BACKEND_HEX \
		-Wall \
		-Wno-unused-value \
		-Wno-pointer-sign \
		-Wno-compare-distinct-pointer-types \
		-Werror \
		-O2 -c -o xdp_lb_kern.o load_balancer.c

load-ebpf-utilities:
	docker exec $(WORKER) apt update
	docker exec $(WORKER) apt install -y bpftool tcpdump

load-ebpf: build-ebpf
	docker cp xdp_lb_kern.o $(WORKER):/xdp_lb_kern.o
	@BACKEND_IP="$${BACKEND_IP:-$$(kubectl get pod -l $(WEBSERVER_SELECTOR) -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)}"; \
	BACKEND_IP="$${BACKEND_IP:-$(DEFAULT_BACKEND_IP)}"; \
	echo "Loading filters for backend $$BACKEND_IP via VIP $(VIP_IP)"; \
	docker exec $(WORKER) sh -lc '\
		set -eu; \
		mountpoint -q /sys/fs/bpf || mount -t bpf bpf /sys/fs/bpf; \
		rm -rf "$(BPF_PIN_DIR)"; \
		mkdir -p "$(BPF_PIN_DIR)"; \
		bpftool prog loadall /xdp_lb_kern.o "$(BPF_PIN_DIR)" type classifier; \
		ip route replace "$(VIP_IP)"/32 dev cni0; \
		ip neigh replace "$(VIP_IP)" lladdr $$(cat /sys/class/net/cni0/address) dev cni0 nud permanent; \
		tc qdisc replace dev cni0 clsact; \
		tc filter replace dev cni0 egress pref 1 handle 1 bpf da pinned "$(BPF_PIN_DIR)/tc_cni0_egress"; \
		INGRESS_DEVS=""; \
		for dev_path in /sys/class/net/lxc*; do \
			[ -e "$$dev_path" ] || continue; \
			dev=$${dev_path##*/}; \
			tc qdisc replace dev "$$dev" clsact; \
			tc filter replace dev "$$dev" ingress pref 1 handle 1 bpf da pinned "$(BPF_PIN_DIR)/tc_lxc_ingress"; \
			INGRESS_DEVS="$$INGRESS_DEVS $$dev"; \
		done; \
		echo "Attached tc_cni0_egress on cni0 and tc_lxc_ingress on$${INGRESS_DEVS:- no lxc interfaces}"; \
	'

all: load-ebpf-utilities load-ebpf

tail-bfp-logs:
	sudo cat /sys/kernel/debug/tracing/trace_pipe

clean:
	rm -rf xdp_lb_kern.o xdp_lb_kern.ll
