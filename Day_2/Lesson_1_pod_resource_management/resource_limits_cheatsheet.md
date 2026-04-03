## 📄 Student Cheat Sheet: Resource Management

### 1. Key Terminology
* **OOMKilled:** Your pod tried to take more Memory than its **Limit**. The kernel killed it.
* **CPU Throttling:** Your pod tried to use more CPU than its **Limit**. K8s just slowed it down (it won't crash, but it will be slow).
* **Pending:** If your **Request** is higher than any available space on your Nodes, the Pod will sit in "Pending" forever.

### 2. Units Reference
| Unit | Meaning | Example |
| :--- | :--- | :--- |
| `1000m` | 1 Full CPU Core | `requests.cpu: 250m` (1/4 Core) |
| `Mi` | Mebibyte (Base 2) | `limits.memory: 512Mi` |
| `Gi` | Gibibyte (Base 2) | `limits.memory: 2Gi` |

### 3. Debugging Commands
```bash
# See resources used by Nodes
kubectl top nodes

# See resources used by Pods (if Metrics Server is installed)
kubectl top pods

# Check if a Namespace has a Quota
kubectl get quota

# See why a Pod died
kubectl describe pod <name> | grep -A 5 "Last State"
```

1. QoS Class Summary

| Class | Rule | Eviction Priority|
| --- | --- | --- |
| Guaranteed | Requests == Limits (CPU & Mem) | Lowest (Safe) |
| Burstable | Requests < Limits (or partial) | Medium |
| BestEffort | No Requests / No Limits | Highest (First to die) |

2. How to Check a Pod's QoS

```sh
# Detailed view (look for qosClass at the bottom)
kubectl describe pod <pod-name>

# Quick view (using jsonpath)
kubectl get pod <pod-name> -o jsonpath='{.status.qosClass}'
```


3. Pro-Tip for Production

Always aim for **Guaranteed** for critical infrastructure (like databases or core APIs) and **Burstable** for general web traffic.
Avoid **BestEffort** in production unless the task is truly unimportant (like a background cleanup script).
