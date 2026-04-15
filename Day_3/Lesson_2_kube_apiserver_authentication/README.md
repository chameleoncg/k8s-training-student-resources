## Kubernetes API Server Authentication & Authorization (RBAC)

These demonstrations are designed to help show to work with the Kubernetes API Server to create individual users and control their access to the cluster with Role Based Access Control (RBAC)

## Setup

1. Create a new cluster

```bash
kind create cluster
```

2. Deploy the jedi

```bash
kubectl apply -f manifests/
```

## Lab 01 - Creating a new Kubernetes User using x509 Certificates

In this lab, we will create a new user identified by a client certificate signed by the kubernetes api server.

1. Create a x509 certificate signing request (csr)

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout luke.key -out luke.csr -subj "/CN=Luke Skywalker/O=Jedi/O=Rebel Alliance"
```

2. Create a Kubernetes CertificateSigningRequest for the x509 csr

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: luke-skywalker
spec:
  request: $(cat luke.csr | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF
```

3. Approve the CSR

```bash
kubectl certificate approve luke-skywalker
```

4. Get the signed certificate

```bash
kubectl get csr luke-skywalker -o jsonpath='{.status.certificate}' | base64 -d > luke.crt
```

5. Add the credentials

```bash
kubectl config set-credentials luke-skywalker --client-key=luke.key --client-certificate=luke.crt --embed-certs=true
```

6. Add the context
```bash
kubectl config set-context luke-skywalker --cluster=kind-kind --user=luke-skywalker
```

7. Verify context
```bash
kubectl --context luke-skywalker auth whoami
```

## Lab 02 - RBAC

Now that we have a user identified by the client certificate, we need to give them access to specific resources within the cluster

1. Create pre-configured roles

Apply the 3 pre-configured roles for the `jedi` namespace:

```bash
kubectl apply -f role-jedi-council.yaml
kubectl apply -f role-jedi-master.yaml
kubectl apply -f role-jedi.yaml
```

2. Create a RoleBinding for any user in the jedi group to the jedi role

```bash
kubectl apply -f rolebinding-jedi.yaml
```

3. Verify Luke has access to resources within the Jedi Namespace

```bash
kubectl --context luke-skywalker get all -n jedi
```

You should see the following.
```
Error from server (Forbidden): replicationcontrollers is forbidden: User "Luke Skywalker" cannot list resource "replicationcontrollers" in API group "" in the namespace "jedi"
Error from server (Forbidden): daemonsets.apps is forbidden: User "Luke Skywalker" cannot list resource "daemonsets" in API group "apps" in the namespace "jedi"
Error from server (Forbidden): deployments.apps is forbidden: User "Luke Skywalker" cannot list resource "deployments" in API group "apps" in the namespace "jedi"
Error from server (Forbidden): replicasets.apps is forbidden: User "Luke Skywalker" cannot list resource "replicasets" in API group "apps" in the namespace "jedi"
Error from server (Forbidden): statefulsets.apps is forbidden: User "Luke Skywalker" cannot list resource "statefulsets" in API group "apps" in the namespace "jedi"
Error from server (Forbidden): horizontalpodautoscalers.autoscaling is forbidden: User "Luke Skywalker" cannot list resource "horizontalpodautoscalers" in API group "autoscaling" in the namespace "jedi"
Error from server (Forbidden): cronjobs.batch is forbidden: User "Luke Skywalker" cannot list resource "cronjobs" in API group "batch" in the namespace "jedi"
Error from server (Forbidden): jobs.batch is forbidden: User "Luke Skywalker" cannot list resource "jobs" in API group "batch" in the namespace "jedi"
```
If you look at the jedi role in `role-jedi.yaml`, this makes sense. The jedi role only has permission to work with `pods`, `services`, `configmaps`, `persistentvolumeclaims`, and `events`.

4. **TRY YOURSELF**

Create a new RoleBinding that will allow luke skywalker to use the `jedi-master` role. Note how he still cannot view secrets within the jedi namespace.

Next, create a RoleBinding that will allow luke skywalker to use the `jedi-council` role. Note how he now has full access to resources within the namespace, including secrets
