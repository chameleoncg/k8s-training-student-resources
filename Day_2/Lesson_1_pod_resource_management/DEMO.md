# Demo Guide: Pod Resource Management

This demo walks through the manifests in `manifests/` to show how Kubernetes handles:

- **Resource requests and limits**
- **Namespace resource quotas**
- **QoS (Quality of Service) classes**

## Prerequisites

- A working Kubernetes cluster
- `kubectl` configured to point at your cluster
- Permissions to create pods/deployments/resourcequotas in your target namespace

## 1) Inspect the manifests

Files used in this lesson:

- `manifests/quota.yaml` – defines a `ResourceQuota` (`student-quota`)
- `manifests/resource-pod.yaml` – pod with tight memory limit designed to trigger OOM behavior
- `manifests/qos.yaml` – three pods showing BestEffort, Burstable, Guaranteed QoS
- `manifests/deployment.yaml` – deployment with equal requests/limits (Guaranteed QoS style)

(Optional) Preview before applying:

```sh
kubectl apply --dry-run=client -f manifests/quota.yaml
kubectl apply --dry-run=client -f manifests/resource-pod.yaml
kubectl apply --dry-run=client -f manifests/qos.yaml
kubectl apply --dry-run=client -f manifests/deployment.yaml
```

---

## 2) Run QoS class demo

Apply all three QoS example pods:

```sh
kubectl apply -f manifests/qos.yaml
kubectl get pods
```

Check each pod’s QoS class:

```sh
kubectl get pod qos-best-effort -o jsonpath='{.status.qosClass}{"\n"}'
kubectl get pod qos-burstable -o jsonpath='{.status.qosClass}{"\n"}'
kubectl get pod qos-guaranteed -o jsonpath='{.status.qosClass}{"\n"}'
```

### Expected mapping

- `qos-best-effort` → `BestEffort`
- `qos-burstable` → `Burstable`
- `qos-guaranteed` → `Guaranteed`

---

## 3) Apply namespace quota

Apply the quota first so its constraints are active:

```sh
kubectl apply -f manifests/quota.yaml
kubectl get resourcequota
kubectl describe resourcequota student-quota
```

### What to look for

- Hard limits for:
  - `pods`
  - `requests.cpu`
  - `requests.memory`
  - `limits.cpu`
  - `limits.memory`
- Used values should update as you create workloads.

---

## 4) Run the stress pod (limits demo)

This pod intentionally requests low memory but tries to consume more than its memory limit.

```sh
kubectl apply -f manifests/resource-pod.yaml
kubectl get pod stress-pod -w
```

Once it fails/restarts, inspect details:

```sh
kubectl describe pod stress-pod
kubectl logs stress-pod --previous
```

### Expected outcome

- Pod may enter `OOMKilled` / restart behavior
- You should see evidence of memory limit enforcement in pod status/events

---

## 5) Apply deployment (requests/limits in a controller)

```sh
kubectl apply -f manifests/deployment.yaml
kubectl get deploy nginx-deployment
kubectl get pods -l app=nginx
kubectl describe pod -l app=nginx
```

### What to look for

- Deployment creates pods with CPU/memory requests and limits set
- Requests and limits are equal in this manifest (Guaranteed behavior pattern)

---

## 6) Verify quota consumption after workloads

```sh
kubectl describe resourcequota student-quota
```

### Discussion points

- How many pods are now counted against quota?
- Are CPU/memory request and limit totals close to quota caps?
- Which workload would fail first if you scale further?

---

## 7) Optional: trigger quota rejection (class exercise)

Try scaling or creating extra pods to exceed quota:

```sh
kubectl scale deployment nginx-deployment --replicas=3
kubectl get events --sort-by=.lastTimestamp
```

Expected: Kubernetes rejects scheduling/creation once quota hard limits are exceeded.

> If this does not fail in your environment, increase replicas further or create an additional pod with explicit requests/limits.

---

## 8) Cleanup

```sh
kubectl delete -f manifests/deployment.yaml --ignore-not-found
kubectl delete -f manifests/qos.yaml --ignore-not-found
kubectl delete -f manifests/resource-pod.yaml --ignore-not-found
kubectl delete -f manifests/quota.yaml --ignore-not-found
```

Confirm cleanup:

```sh
kubectl get pods
kubectl get resourcequota
```

---

## Troubleshooting

- **Pod stuck `Pending`**: likely insufficient cluster resources or quota constraints.
- **`Error from server (Forbidden)` on create**: quota or policy is blocking the object.
- **No `kubectl top` output**: metrics server may not be installed (not required for this demo).
