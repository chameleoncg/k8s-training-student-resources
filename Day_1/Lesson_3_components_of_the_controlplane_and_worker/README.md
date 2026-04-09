# Components of the Controlplane and worker

## Part 1: Discover the Control Plane

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl describe pod kube-api-server-node_name
kubectl get leases -n kube-system
```

## Part 2: Watch the Controller-Manager React

```bash
kubectl create deployment nginx-test --image=nginx --replicas=3
kubectl get pods -w
kubectl delete pod $(kubectl get pods -l app=nginx-test -o name | head -1)
kubectl get events --sort-by=.metadata.creationTimestamp | tail
```

## Part 3: Inspect a Node

```bash
kubectl describe node node_name
```