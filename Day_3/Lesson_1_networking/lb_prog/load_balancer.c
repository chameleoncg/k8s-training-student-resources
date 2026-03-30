#include "load_balancer.h"

#define SVC_VIP_IP __constant_htonl(0x0af4fffb)      /* 10.244.255.251 */
#define SVC_VIP_PORT __constant_htons(8080)
#define POD_CIDR_IP __constant_htonl(0x0af40000)     /* 10.244.0.0 */
#define POD_CIDR_MASK __constant_htonl(0xffff0000)   /* /16 */
#ifndef REAL_BACKEND_RAW_IP
#define REAL_BACKEND_RAW_IP 0x0af40003 /* 10.244.0.3 */
#endif
#define REAL_BACKEND_IP __constant_htonl(REAL_BACKEND_RAW_IP)
#define REAL_BACKEND_PORT __constant_htons(8080)

static __always_inline int is_pod_ip(__u32 addr)
{
    return (addr & POD_CIDR_MASK) == POD_CIDR_IP;
}

SEC("tc_ingress")
int tc_lxc_ingress(struct __sk_buff *skb)
{
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct ethhdr *eth;
    struct iphdr *ip;
    struct tcphdr *tcp;

    if (parse_ipv4_tcp(data, data_end, &eth, &ip, &tcp) < 0)
        return TC_ACT_OK;

    // Reply path: rewrite to the original IP so conntrack does the rest
    if (ip->saddr == REAL_BACKEND_IP && tcp->source == REAL_BACKEND_PORT) {
        __u32 old_ip = ip->saddr;
        __u32 new_ip = SVC_VIP_IP;

        ip->saddr = new_ip;
        update_ipv4_tcp_csum(old_ip, new_ip, ip, tcp);
        bpf_printk("RPL rewrite src=%d dst=%d", __builtin_bswap16(tcp->source), __builtin_bswap16(tcp->dest));
        return TC_ACT_OK;
    }

    return TC_ACT_OK;
}

SEC("tc_egress")
int tc_cni0_egress(struct __sk_buff *skb)
{
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct ethhdr *eth;
    struct iphdr *ip;
    struct tcphdr *tcp;

    if (parse_ipv4_tcp(data, data_end, &eth, &ip, &tcp) < 0)
        return TC_ACT_OK;

    // Request path: rewrite to the backend IP and redirect to the next hop
    if (is_pod_ip(ip->saddr) &&
        ip->daddr == SVC_VIP_IP &&
        tcp->dest == SVC_VIP_PORT) {
        __u32 old_ip = ip->daddr;
        __u32 new_ip = REAL_BACKEND_IP;
        __u32 old_ports;
        __u32 new_ports;

        __builtin_memcpy(&old_ports, &tcp->source, sizeof(old_ports));
        ip->daddr = new_ip;
        tcp->dest = REAL_BACKEND_PORT;
        __builtin_memcpy(&new_ports, &tcp->source, sizeof(new_ports));

        update_ipv4_tcp_csum(old_ip, new_ip, ip, tcp);
        update_tcp_ports_csum(old_ports, new_ports, tcp);
        bpf_printk("REQ rewrite src=%d dst=%d", __builtin_bswap16(tcp->source), __builtin_bswap16(tcp->dest));
        return bpf_redirect_neigh(skb->ifindex, NULL, 0, 0);
    }

    return TC_ACT_OK;
}

char _license[] SEC("license") = "GPL";
