## 📄 Student Cheat Sheet: Common Primitives

### 1. Resource Comparison
| Resource | Purpose | Best for... |
| :--- | :--- | :--- |
| **Deployment** | Stateless scaling | Web apps, APIs |
| **StatefulSet** | Persistent identity | Databases (Postgres, Mongo) |
| **DaemonSet** | Node-level tools | Logging (Fluentd), Monitoring |
| **Job** | One-off tasks | DB Migrations, Backups |
| **CronJob** | Scheduled tasks | Nightly reports, cleanup |

### 2. Service Discovery
* **The Selector:** Services find Pods by matching **Labels**.
* **Internal DNS:** You can reach a service via its name: `http://my-service-name`.

### 3. Essential Commands
```bash
# NAMESPACES
kubectl get ns                     # List all namespaces
kubectl config set-context --current --namespace=my-team # Switch default ns

# SERVICES
kubectl get svc                    # List services
kubectl describe svc <name>        # See the Endpoints (which pods are linked)

# CONFIG & SECRETS
kubectl create configmap my-config --from-literal=color=red
kubectl create secret generic my-secret --from-literal=password=1234
```

### 4. Configuration Injection Pattern
To use a ConfigMap in a Pod spec:
```yaml
env:
  - name: APP_COLOR
    valueFrom:
      configMapKeyRef:
        name: my-config
        key: color
```
