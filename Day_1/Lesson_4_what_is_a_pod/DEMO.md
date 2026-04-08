# Demo Guide: What is a Pod?

This demo walks you through the manifests in this lesson and helps you observe:
- A single-container Pod
- A multi-container Pod with an init container and sidecar behavior
- Shared Pod networking and storage concepts

## Prerequisites

- A working Kubernetes cluster
- `kubectl` configured to that cluster
- Access to this lesson folder

---

## Part 1: Basic Pod Demo (`manifests/basic-pod.yaml`)

### 1) Create the Pod
Run:

`kubectl apply -f manifests/basic-pod.yaml`

### 2) Confirm it is running
Run:

`kubectl get pods -o wide`

You should see `basic-nginx` in `Running` status.

### 3) Inspect Pod details
Run:

`kubectl describe pod basic-nginx`

Focus on:
- `Containers` section
- Image used (`nginx:latest`)
- Pod IP and events

### 4) Check logs
Run:

`kubectl logs basic-nginx`

For nginx, logs may be minimal until traffic reaches the pod.

### 5) (Optional) Port-forward and test
Run:

`kubectl port-forward pod/basic-nginx 8080:80`

Then visit `http://localhost:8080` in your browser or use `curl http://localhost:8080` to confirm nginx is serving traffic.

Stop port-forward with `Ctrl+C` when done.

### 6) Cleanup basic pod
Run:

`kubectl delete -f manifests/basic-pod.yaml`

---

## Part 2: Multi-Container Pod Demo (`manifests/multi-container-pod.yaml`)

This manifest demonstrates:
- `initContainers` (run first, must complete)
- Main app container (`web-server`)
- Sidecar-style container (`log-sidecar`)
- Shared volumes using `emptyDir`

### 1) Create the Pod
Run:

`kubectl apply -f manifests/multi-container-pod.yaml`

### 2) Watch Pod lifecycle
Run:

`kubectl get pods -w`

You may briefly see init-related status before `Running`.

Stop watch with `Ctrl+C` once running.

### 3) Describe the pod to verify init container completion
Run:

`kubectl describe pod multi-container-demo`

Focus on:
- Init container state (should show completed)
- Two running app containers
- Mounted volumes

### 4) Verify init container output is served by nginx
The init container writes an `index.html` file into shared storage, and nginx serves it.

Run:

`kubectl port-forward pod/multi-container-demo 8081:80`

Open `http://localhost:8081` or `wget http://localhost:8081` and confirm the page content includes:

`Hello from the Init Container!`

Stop port-forward with `Ctrl+C`.

### 5) Inspect logs from specific containers
Run:

`kubectl logs multi-container-demo -c web-server`

Run:

`kubectl logs multi-container-demo -c log-sidecar`

The sidecar continuously writes timestamps to `/var/log/app.log`.

### 6) Exec into the sidecar and inspect the generated log file
Run:

`kubectl exec -it multi-container-demo -c log-sidecar -- sh`

Then inside the container:

`tail -n 20 /var/log/app.log`

Exit shell with:

`exit`

### 7) Cleanup multi-container pod
Run:

`kubectl delete -f manifests/multi-container-pod.yaml --grace-period=0 --force`

---

## Key Teaching Points to Call Out During Demo

1. **Pod = smallest deployable unit** in Kubernetes.
2. **Containers in the same Pod share network namespace** (same IP, communicate via `localhost`).
3. **Init containers run to completion before main containers start**.
4. **Sidecar pattern**: helper container runs alongside the main app.
5. **`emptyDir` volumes are ephemeral** and deleted when the Pod is removed.

---

## Troubleshooting Tips (if demo behaves unexpectedly)

- Check events:

`kubectl describe pod <pod-name>`

- Check current status:

`kubectl get pods -o wide`

- If image pull issues appear, verify cluster internet/image registry access.
- If a pod is stuck `Pending`, verify cluster resources and node readiness.
