WORKER ?= training-worker
VIP_IP ?= 10.244.255.251
BPF_PIN_DIR ?= /sys/fs/bpf/lb_prog

build-ebpf:
	@BACKEND_IP=$$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true); \
	if [ -n "$$BACKEND_IP" ]; then \
		BACKEND_HEX=$$(printf '0x%02x%02x%02x%02x' $$(echo $$BACKEND_IP | tr '.' ' ')); \
	else \
		BACKEND_IP="10.244.0.3"; \
		BACKEND_HEX="0x0af40003"; \
	fi; \
	echo "Building xdp_lb_kern.o with backend $$BACKEND_IP ($$BACKEND_HEX)"; \
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
# 	llc -march=bpf -filetype=obj -o xdp_lb_kern.o xdp_lb_kern.ll

load-ebpf-utilities:
	docker exec $(WORKER) apt update
	docker exec $(WORKER) apt install -y bpftool tcpdump

load-ebpf:
	docker cp xdp_lb_kern.o $(WORKER):/xdp_lb_kern.o
	@BACKEND_IP=$$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].status.podIP}'); \
	echo "Loading filters for backend $$BACKEND_IP"; \
	docker exec $(WORKER) sh -lc '\
		set -eu; \
		mountpoint -q /sys/fs/bpf || mount -t bpf bpf /sys/fs/bpf; \
		rm -rf "$(BPF_PIN_DIR)"; \
		mkdir -p "$(BPF_PIN_DIR)"; \
		bpftool prog loadall /xdp_lb_kern.o "$(BPF_PIN_DIR)" type classifier; \
		ip route replace $(VIP_IP)/32 dev cni0; \
		ip neigh replace $(VIP_IP) lladdr $$(cat /sys/class/net/cni0/address) dev cni0 nud permanent; \
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

all: build-ebpf load-ebpf-utilities load-ebpf

tail-bfp-logs:
	sudo cat /sys/kernel/debug/tracing/trace_pipe

clean:
	rm -rf xdp_lb_kern.o xdp_lb_kern.ll
