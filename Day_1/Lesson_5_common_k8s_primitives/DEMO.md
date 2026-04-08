# Demo Guide: Common Kubernetes Primitives

This demo walks through three core concepts in this lesson:

1. **Deployments** (scaling and self-healing)
2. **Services** (stable networking to Pods)
3. **ConfigMap + Secret injection** (configuration into containers)

---

## Prerequisites

- A working Kubernetes cluster
- `kubectl` configured to target your cluster
- You are in this folder:

```sh
cd Day_1/Lesson_5_common_k8s_primitives
```

---

## Files Used

- `manifests/deployment-healing.yaml`
- `manifests/service.yaml`
- `manifests/config-and-secret.yaml`
- `manifests/injection-deployment.yaml`

---

## 1) Deployment Demo (Scaling + Self-Healing)

### Step 1: Create the Deployment

```sh
kubectl apply -f manifests/deployment-healing.yaml
```

### Step 2: Verify resources

```sh
kubectl get deploy
kubectl get pods -l app=nginx -o wide
kuebctl get replicasets.apps
```

You should see:
- Deployment: `nginx-deployment`
- Replicas: `3`
- Multiple Pods with label `app=nginx`

### Step 3: Demonstrate self-healing

Delete one Pod and watch Kubernetes replace it.

```sh
kubectl delete pod <one-of-the-nginx-pod-names>
kubectl get pods -l app=nginx -w
```

Expected behavior:
- One Pod terminates
- A new Pod is created automatically to maintain desired replica count

### Optional: Scale up/down manually

```sh
kubectl scale deployment nginx-deployment --replicas=5
kubectl get pods -l app=nginx
kubectl scale deployment nginx-deployment --replicas=3
```

---

## 2) Service Demo (Stable Access to Pods)

### Step 1: Create the Service

```sh
kubectl apply -f manifests/service.yaml
```

### Step 2: Inspect the Service and Endpoints

```sh
kubectl get svc nginx-service
kubectl describe svc nginx-service
```

What to highlight:
- Service type: `ClusterIP`
- Selector: `app=nginx`
- Endpoints should list Pod IPs from the Deployment

### Step 3: Test in-cluster connectivity (optional)

If you want to test from inside the cluster:

```sh
kubectl run curl-test --image=curlimages/curl:8.10.1 --rm -it --restart=Never -- sh
```

Inside the shell:

```sh
curl -I http://nginx-service
exit
```

Expected behavior:
- Request resolves and reaches one of the nginx Pods through the Service

---

## 3) Config Injection Demo (ConfigMap + Secret)

### Step 1: Create ConfigMap and Secret

```sh
kubectl apply -f manifests/config-and-secret.yaml
kubectl get configmap app-config
kubectl get secret app-secret
```

### Step 2: Create Deployment that consumes config

```sh
kubectl apply -f manifests/injection-deployment.yaml
kubectl get pods -l app=config-test
```

### Step 3: Verify env vars were injected

```sh
kubectl logs deploy/config-demo --tail=50
```

Look for:
- `MY_COLOR=...` (from ConfigMap key `APP_COLOR`)
- `MY_PASSWORD=...` (from Secret key `API_KEY`)

> Note: This demo image prints environment variables in a loop for inspection.

---

## Cleanup

```sh
kubectl delete -f manifests/injection-deployment.yaml
kubectl delete -f manifests/config-and-secret.yaml
kubectl delete -f manifests/service.yaml
kubectl delete -f manifests/deployment-healing.yaml
```

---

## Troubleshooting Tips

- If Pods are not running:
  ```sh
  kubectl describe pod <pod-name>
  kubectl logs <pod-name>
  ```
- If Service has no endpoints:
  - Check labels on Pods:
    ```sh
    kubectl get pods --show-labels
    ```
  - Confirm selector in `service.yaml` matches Pod labels
- If env vars are missing:
  - Confirm ConfigMap/Secret names and keys match deployment references exactly

---

## Presenter Notes (Optional Talking Points)

- **Deployment** manages desired state and self-healing behavior.
- **Service** decouples Pod lifecycle from network access.
- **ConfigMap/Secret injection** separates config from container images for portability and security.
