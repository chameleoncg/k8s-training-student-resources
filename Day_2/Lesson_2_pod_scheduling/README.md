# Contested Scheduling Lab

This lab will setup a 2 node cluster and be setup to run at capacity (kubelet is fixed to 4 pods per node)

```mermaid
flowchart LR
    subgraph one ["training-worker (max pods=4)"]
        kubeproxy1["kubeproxy"]        
        kindnet1["kindnet"]        
        webserver1
        webserver2
    end
    subgraph two ["training-worker2 (max pods=4)"]
        hpc_label["training/hpc=true"]
        kubeproxy2["kubeproxy"]        
        kindnet2["kindnet"]        
        webserver3
        webserver4
    end

    one ~~~ two
    kubeproxy1 ~~~ kindnet1
    kubeproxy2 ~~~ kindnet2
    webserver1 ~~~ webserver2
    webserver3 ~~~ webserver4
```

## Setup

```bash
make clean cluster
kubectl apply -f manifests/contested-scheduling.yaml
```

## Challenge

The goal is to apply the new "hpc" deployment, and convince the scheduler the following:

* To run on the HPC labelled node
* To evict the existing workloads from the node

```bash
kubectl apply -f manifests/hpc-api.yaml
```