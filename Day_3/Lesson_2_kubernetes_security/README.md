# K8s Security Labs

> **Prerequisites:** These labs assume your Kind cluster is running with the Cilium CNI.
> Cilium enforces NetworkPolicies. Without a CNI that supports enforcement, the Network
> Policy lab will not work as expected.

---

## Lab 1: RBAC — Least Privilege for ServiceAccounts

This lab focuses on RBAC for ServiceAccounts — the identity mechanism for workloads running
inside the cluster. The authentication session covered user-based RBAC. Here we apply the
same concepts to the pods themselves.

### Part 1: Examine the RBAC Resources

Before applying anything, read through the manifests so you understand what each one does.

```bash
cat manifests/01-rbac-role.yaml
```

```bash
cat manifests/02-rbac-rolebinding.yaml
```

```bash
cat manifests/03-serviceaccount.yaml
```

**Q: What verbs does the `pod-reader` Role allow? What resources does it grant access to?**

### Part 2: Create the ServiceAccount, Role, and RoleBinding

```bash
kubectl apply -f manifests/03-serviceaccount.yaml
```

```bash
kubectl apply -f manifests/01-rbac-role.yaml
```

```bash
kubectl apply -f manifests/02-rbac-rolebinding.yaml
```


### Part 3: Test Permissions from Outside the Pod

Before deploying a pod, use `kubectl auth can-i` with `--as` to impersonate the ServiceAccount
and check what it can do:

```bash
kubectl auth can-i --list --as=system:serviceaccount:default:lab-viewer
```

Spot-check specific actions:

```bash
kubectl auth can-i get pods --as=system:serviceaccount:default:lab-viewer
```
Expected: `yes`

```bash
kubectl auth can-i create pods --as=system:serviceaccount:default:lab-viewer
```
Expected: `no`

```bash
kubectl auth can-i get secrets --as=system:serviceaccount:default:lab-viewer
```
Expected: `no`

```bash
kubectl auth can-i list deployments --as=system:serviceaccount:default:lab-viewer
```
Expected: `no`

**Key takeaway:** The ServiceAccount can ONLY do what the Role explicitly allows. Everything
else is denied. RBAC is additive — there are no deny rules.

### Part 4: Test from Inside a Pod

Deploy a pod running as the `lab-viewer` ServiceAccount and verify that the permissions
work the same way from inside the cluster:

```bash
kubectl apply -f manifests/04-test-pod.yaml
```


```bash
kubectl exec -it rbac-test-pod -- sh
```

Run these commands **inside the pod**:

```bash
kubectl get pods
```

These should all fail with "Forbidden":

```bash
kubectl get secrets
```

```bash
kubectl get deployments
```

```bash
kubectl create configmap test --from-literal=key=val
```

```bash
kubectl delete pod rbac-test-pod
```

```
Expected output for forbidden actions:
Error from server (Forbidden): secrets is forbidden: User
"system:serviceaccount:default:lab-viewer" cannot list resource
"secrets" in API group "" in the namespace "default"
```

Exit the pod when done:

```bash
exit
```

### Part 5: Escalate — Grant Secrets Access

Now see what happens when you grant `get secrets` permission to the same ServiceAccount.
This demonstrates why secrets access is one of the most sensitive RBAC permissions.

First, create a secret for the SA to find:

```bash
kubectl apply -f manifests/07-opaque-secret.yaml
```

Verify the SA cannot read it yet:

```bash
kubectl auth can-i get secrets --as=system:serviceaccount:default:lab-viewer
```
Expected: `no`

Now grant secrets access:

```bash
kubectl apply -f manifests/05-rbac-role-secret-reader.yaml
```

```bash
kubectl apply -f manifests/06-rbac-rolebinding-secret-reader.yaml
```

Check again:

```bash
kubectl auth can-i get secrets --as=system:serviceaccount:default:lab-viewer
```
Expected: `yes` — the new RoleBinding added this permission

Test from inside the pod — the permissions update immediately, no pod restart needed:

```bash
kubectl exec -it rbac-test-pod -- sh
```

Inside the pod:

```bash
kubectl get secrets
```

```bash
kubectl get secret lab-secret -o jsonpath='{.data.db-password}' | base64 -d
```
Expected output: `sUp3rS3cr3t!`

**Key takeaway:** A single RoleBinding just gave this pod access to every secret in the
namespace. In a real cluster, a compromised pod with this binding can exfiltrate all
passwords, tokens, and API keys. This is why least-privilege RBAC matters.

Exit the pod:

```bash
exit
```

### Part 6: TRY YOURSELF — Cross-Namespace Denial

Test that the ServiceAccount's permissions do NOT extend to other namespaces:

```bash
kubectl create namespace rbac-test
```

```bash
kubectl run test-pod --namespace rbac-test --image=nginx:latest
```

```bash
kubectl auth can-i get pods --namespace rbac-test --as=system:serviceaccount:default:lab-viewer
```
Expected: `no` — the RoleBinding only applies to the default namespace

### Cleanup

```bash
kubectl delete pod rbac-test-pod
```

```bash
kubectl delete rolebinding read-pods-binding read-secrets-binding
```

```bash
kubectl delete role pod-reader secret-reader
```

```bash
kubectl delete serviceaccount lab-viewer
```

```bash
kubectl delete secret lab-secret
```

```bash
kubectl delete namespace rbac-test
```

---

## Lab 2: Secrets — Base64 is NOT Encryption


### Part 1: Create and Inspect a Secret

```bash
kubectl apply -f manifests/07-opaque-secret.yaml
```

Look at the secret — the data is base64-encoded, NOT encrypted:

```bash
kubectl get secret lab-secret -o yaml
```

Notice the `data` field. The values look scrambled, but base64 is trivially reversible:

```bash
kubectl get secret lab-secret -o jsonpath='{.data.db-password}' | base64 -d && echo
```
Expected output: `sUp3rS3cr3t!`

```bash
kubectl get secret lab-secret -o jsonpath='{.data.api-key}' | base64 -d && echo
```
Expected output: `abc123xyz789`

```bash
kubectl get secret lab-secret -o jsonpath='{.data.connection-string}' | base64 -d && echo
```
Expected output: `postgresql://user:sUp3rS3cr3t!@db-host:5432/mydb`

Now compare what `describe` shows vs `-o yaml`. `describe` intentionally hides the values
(shows byte count only):

```bash
kubectl describe secret lab-secret
```

Anyone with RBAC `get` on secrets can use `-o yaml` or `-o jsonpath` to decode them — this
is why RBAC on secrets matters.

### Part 2: Consume a Secret in a Pod

```bash
kubectl apply -f manifests/08-secret-consumer-pod.yaml
```

```bash
kubectl exec -it secret-consumer -- sh
```

Inside the pod, compare both consumption methods.

Method 1 — Environment variable:

```bash
env | grep DB_PASSWORD
```
Expected: `DB_PASSWORD=sUp3rS3cr3t!`

```bash
env | grep API_KEY
```
Expected: `API_KEY=abc123xyz789`

Method 2 — Volume mount (each key is a file):

```bash
ls /etc/secrets/
```

```bash
cat /etc/secrets/db-password
```

```bash
cat /etc/secrets/api-key
```

```bash
cat /etc/secrets/connection-string
```

Exit the pod:

```bash
exit
```

### Part 3: Update Propagation — Volume Mounts vs Env Vars

This demonstrates a critical operational difference: volume-mounted secrets update
automatically, but environment variables are frozen at pod startup.

Update the secret value:

```bash
kubectl patch secret lab-secret -p '{"stringData":{"db-password":"N3wP@ssw0rd!"}}'
```

Wait about 30-60 seconds for the kubelet to sync the volume mount, then check:

```bash
kubectl exec secret-consumer -- cat /etc/secrets/db-password
```
Expected output (after sync): `N3wP@ssw0rd!` — updated!

```bash
kubectl exec secret-consumer -- sh -c 'echo $DB_PASSWORD'
```
Expected output: `sUp3rS3cr3t!` — still the OLD value (env vars never update)

**Key takeaway:** Prefer volume mounts for any secret that rotates (certificates, tokens,
passwords). Env vars require a pod restart to pick up new values.

### Cleanup

```bash
kubectl delete pod secret-consumer
```

```bash
kubectl delete secret lab-secret
```

---

## Lab 3: Network Policies — Trust No Pod

> **Note:** This lab requires a CNI that enforces NetworkPolicies. Your cluster uses
> Cilium, which fully supports NetworkPolicy enforcement.

### Part 1: Establish Baseline Connectivity

Deploy a server and a client, then verify they can communicate freely:

```bash
kubectl apply -f manifests/11-server-pod.yaml
```

```bash
kubectl apply -f manifests/12-client-pod.yaml
```

Get the server pod's IP:

```bash
SERVER_IP=$(kubectl get pod server-pod -o jsonpath='{.status.podIP}')
echo "Server IP: $SERVER_IP"
```

Verify the client CAN reach the server (should return nginx welcome page HTML):

```bash
kubectl exec client-pod -- curl -s --max-time 5 http://${SERVER_IP}:80
```

You should see the nginx welcome page. Right now there are no NetworkPolicies, so all
pod-to-pod traffic is allowed.

### Part 2: Apply Default-Deny Ingress

This is the standard pattern: deny everything, then allow only what's needed.

Review the policy first — note the empty podSelector (matches ALL pods):

```bash
cat manifests/09-netpol-default-deny.yaml
```

```bash
kubectl apply -f manifests/09-netpol-default-deny.yaml
```

Try again — this should TIME OUT (Cilium is now blocking the traffic):

```bash
kubectl exec client-pod -- curl -s --max-time 5 http://${SERVER_IP}:80
```

```
Expected:
curl: (28) Connection timed out after 5001 milliseconds
Exit code: 28
```

**Key takeaway:** The empty `podSelector: {}` in the deny policy isolates EVERY pod in the
namespace for ingress. This is the correct default-deny pattern — not a targeted selector.

### Part 3: Allow Specific Traffic by Label

Review the allow policy — it permits ingress only from pods with `role=client` on port 80:

```bash
cat manifests/10-netpol-allow-labeled.yaml
```

```bash
kubectl apply -f manifests/10-netpol-allow-labeled.yaml
```

Test again — `client-pod` has the label `role=client`, so this should work:

```bash
kubectl exec client-pod -- curl -s --max-time 5 http://${SERVER_IP}:80
```
Expected: nginx welcome page HTML

### Part 4: Verify Unlabeled Pods Are Still Blocked

Deploy a pod WITHOUT the `role=client` label:

```bash
kubectl run rogue-pod --image=curlimages/curl:latest --command -- sleep 3600
```

Try to reach the server from the unlabeled pod:

```bash
kubectl exec rogue-pod -- curl -s --max-time 5 http://${SERVER_IP}:80
```

```
Expected:
curl: (28) Connection timed out after 5001 milliseconds
```

The rogue-pod does not have `role=client`, so the allow policy does not match it.

### Part 5: TRY YOURSELF — Label the Rogue Pod

Add the `role=client` label to the rogue pod and test again. Does it work now?

```bash
kubectl label pod rogue-pod role=client
```

```bash
kubectl exec rogue-pod -- curl -s --max-time 5 http://${SERVER_IP}:80
```

**Q: What does this tell you about using labels as the basis for network policy?**
Think about what would happen if an attacker can create pods with arbitrary labels in the
namespace.

### Cleanup

```bash
kubectl delete pod server-pod client-pod rogue-pod
```

```bash
kubectl delete networkpolicy default-deny-ingress allow-client-ingress
```

---

## Lab 4: Pod Security — Feel the Guardrails

### Part 1: Inspect a Hardened Pod

Before testing PSA enforcement, examine what a fully hardened securityContext looks like:

```bash
cat manifests/13-security-context-pod.yaml
```

**Q: Identify each security setting and what it does:**
- `runAsUser: 1000` — ?
- `runAsNonRoot: true` — ?
- `readOnlyRootFilesystem: true` — ?
- `allowPrivilegeEscalation: false` — ?
- `capabilities.drop: ["ALL"]` — ?
- `seccompProfile.type: RuntimeDefault` — ?

Deploy it and verify it runs:

```bash
kubectl apply -f manifests/13-security-context-pod.yaml
```

Verify the process is running as UID 1000, not root:

```bash
kubectl exec security-context-demo -- id
```
Expected: `uid=1000 gid=3000 groups=2000`

Verify the filesystem is read-only:

```bash
kubectl exec security-context-demo -- touch /test-file 2>&1
```
Expected: `touch: /test-file: Read-only file system`

### Part 2: Warn Mode — See What Would Break

Before enforcing a standard, use `warn` mode to see violations without blocking anything:

```bash
kubectl label ns default pod-security.kubernetes.io/warn=restricted
```

Deploy the non-compliant pod — it will be ALLOWED but you will see warnings:

```bash
kubectl apply -f manifests/15-non-compliant-pod.yaml
```

```
Expected output (warnings, but the pod is still created):

Warning: would violate PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false (container "app" must set
    securityContext.allowPrivilegeEscalation=false)
  unrestricted capabilities (container "app" must set
    securityContext.capabilities.drop=["ALL"])
  runAsNonRoot != true (pod or container "app" must set
    securityContext.runAsNonRoot=true)
  seccompProfile (pod or container "app" must set
    securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/non-compliant-pod created
```

**Read the warnings carefully.** Each line tells you exactly which field is missing or
misconfigured. This is how you audit existing workloads before turning on enforcement.

Verify the pod is actually running despite the warnings:

```bash
kubectl get pod non-compliant-pod
```
Expected: `Running`

Clean up before moving to enforce mode:

```bash
kubectl delete pod non-compliant-pod
```

```bash
kubectl label ns default pod-security.kubernetes.io/warn-
```

### Part 3: Enforce Mode — Reject Non-Compliant Pods

Now switch to `enforce`. This will reject pods that violate the standard outright.

```bash
kubectl label ns default pod-security.kubernetes.io/enforce=restricted
```

Try the non-compliant pod — it should be REJECTED:

```bash
kubectl apply -f manifests/15-non-compliant-pod.yaml
```

```
Expected output (the pod is NOT created):

Error from server (Forbidden): error when creating "manifests/15-non-compliant-pod.yaml":
pods "non-compliant-pod" is forbidden: violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false (...)
  unrestricted capabilities (...)
  runAsNonRoot != true (...)
  seccompProfile (...)
```

**Q: Compare the error message to the warnings from Part 2. Are they the same violations?**

### Part 4: Deploy a Compliant Pod

Review what makes this pod compliant:

```bash
cat manifests/14-compliant-pod.yaml
```

```bash
kubectl apply -f manifests/14-compliant-pod.yaml
```

```bash
kubectl get pod compliant-pod
```
Expected: `Running` — this pod meets all restricted requirements

### Part 5: TRY YOURSELF — Baseline vs Restricted

Switch the namespace to `baseline` enforcement and test a pod that has no security settings
at all:

```bash
kubectl label ns default pod-security.kubernetes.io/enforce=baseline --overwrite
```

Try a completely unsecured pod (stock nginx, runs as root):

```bash
kubectl apply -f manifests/16-baseline-pod.yaml
```

Does it get created?

Now switch back to restricted:

```bash
kubectl label ns default pod-security.kubernetes.io/enforce=restricted --overwrite
```

Delete the baseline pod and try to recreate it:

```bash
kubectl delete pod baseline-pod
```

```bash
kubectl apply -f manifests/16-baseline-pod.yaml
```

What happens now?

**Q: What does `baseline` allow that `restricted` does not?**

### Cleanup

```bash
kubectl delete pod security-context-demo compliant-pod baseline-pod 2>/dev/null
```

```bash
kubectl label ns default pod-security.kubernetes.io/enforce-
```
