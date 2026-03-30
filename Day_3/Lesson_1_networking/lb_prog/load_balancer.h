#include <stddef.h>
#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/pkt_cls.h>
#include <bpf_helpers.h>
#include <bpf_endian.h>

static __always_inline __u16 csum_fold_helper(__u64 csum)
{
    int i;
#pragma unroll
    for (i = 0; i < 4; i++) {
        if (csum >> 16)
            csum = (csum & 0xffff) + (csum >> 16);
    }
    return ~csum;
}

static __always_inline void update_ipv4_tcp_csum(__u32 old_ip, __u32 new_ip,
                                                  struct iphdr *ip,
                                                  struct tcphdr *tcp)
{
    __u64 l3_csum = (__u64)(~ip->check) & 0xffff;
    l3_csum = bpf_csum_diff(&old_ip, sizeof(old_ip), &new_ip, sizeof(new_ip), l3_csum);
    ip->check = csum_fold_helper(l3_csum);

    __u64 l4_csum = (__u64)(~tcp->check) & 0xffff;
    l4_csum = bpf_csum_diff(&old_ip, sizeof(old_ip), &new_ip, sizeof(new_ip), l4_csum);
    tcp->check = csum_fold_helper(l4_csum);
}

static __always_inline void update_tcp_ports_csum(__u32 old_ports, __u32 new_ports,
                                                   struct tcphdr *tcp)
{
    __u64 l4_csum = (__u64)(~tcp->check) & 0xffff;
    l4_csum = bpf_csum_diff(&old_ports, sizeof(old_ports), &new_ports, sizeof(new_ports), l4_csum);
    tcp->check = csum_fold_helper(l4_csum);
}

static __always_inline int parse_ipv4_tcp(void *data, void *data_end,
                                          struct ethhdr **ethh,
                                          struct iphdr **iph,
                                          struct tcphdr **tcph)
{
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end)
        return -1;

    if (eth->h_proto != __constant_htons(ETH_P_IP))
        return -1;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end)
        return -1;

    if (ip->ihl < 5)
        return -1;

    if (ip->protocol != IPPROTO_TCP)
        return -1;

    struct tcphdr *tcp = (void *)ip + ip->ihl * 4;
    if ((void *)(tcp + 1) > data_end)
        return -1;

    *ethh = eth;
    *iph = ip;
    *tcph = tcp;
    return 0;
}
