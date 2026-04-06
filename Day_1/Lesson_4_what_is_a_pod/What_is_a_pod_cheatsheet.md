
# 🛡️ Kubernetes Cheat Sheet: Lesson 1 - What is a Pod?

## 1. The "Must-Know" Concepts
* **Pod:** The smallest deployable unit in K8s. It’s a wrapper for one or more containers.
* **Ephemeral:** Pods are temporary. If they die, they are replaced, not repaired.
* **Shared Identity:** All containers in a Pod share the same **IP address** and **Storage Volumes**. They talk to each other via `localhost`.

---

## 2. Essential CLI Commands (`kubectl`)
| Command | Purpose |
| :--- | :--- |
| `kubectl get pods` | List all pods in the current namespace. |
| `kubectl get pods -o wide` | List pods with more detail (like Node and IP). |
| `kubectl describe pod <name>` | **The Debugger.** Shows events, lifecycle, and errors. |
| `kubectl logs <name>` | See the stdout/stderr of the container. |
| `kubectl logs <name> -c <container>` | See logs for a specific container in a multi-container pod. |
| `kubectl exec -it <name> -- sh` | Drop into a terminal *inside* the pod. |
| `kubectl apply -f <file>.yaml` | Create or update a pod from a file. |
| `kubectl delete pod <name>` | Terminate a pod (it will be gone forever!). |

---

## 3. Anatomy of a Pod Spec
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app             # Unique name in the namespace
  labels:                  # Key-value pairs for organization
    app: frontend
spec:
  containers:              # The heart of the pod
  - name: nginx-server
    image: nginx:1.21      # Which image to pull
    ports:
    - containerPort: 80    # Port the container listens on
    volumeMounts:          # WHERE to mount the storage inside the container
    - name: data-vol
      mountPath: /data
  volumes:                 # WHAT storage is available to the pod
  - name: data-vol
    emptyDir: {}           # Temporary storage (wiped on pod delete)
```

---

## 4. Special Containers
* **Init-Containers:** Run **sequentially** before the main app starts. If an Init-Container fails, the Pod restarts until it succeeds.
* **Sidecars:** Run **simultaneously** with the main app. Usually used for logging, proxies (Service Mesh), or syncing data.

---

## 5. Troubleshooting 101
If your pod status isn't `Running`, check these:
* **ImagePullBackOff:** K8s can't find the image or you don't have permission to pull it.
* **CrashLoopBackOff:** The container started, but the application inside crashed immediately.
* **Pending:** Usually means there aren't enough resources (CPU/RAM) on the cluster nodes.

> **Pro-Tip:** Use `kubectl get pods --watch` during your demos to see the state changes in real-time!
