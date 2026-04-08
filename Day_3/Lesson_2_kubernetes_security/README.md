# K8s Security Labs

## Lab: RBAC

```bash
# Create the Role and Binding

kubectl apply -f 01-rbac-role.yaml     	# Role: read-only pods in default ns
kubectl apply -f 02-rbac-rolebinding.yaml  # Bind to ServiceAccount lab-viewer
kubectl get role,rolebinding -n default	# Confirm they exist

# Test as the ServiceAccount

kubectl apply -f 03-test-pod-as-sa.yaml	# Pod running as lab-viewer SA
kubectl exec -it rbac-test-pod -- sh
# Inside pod:
kubectl auth can-i get pods 	# Should be: yes
kubectl auth can-i create pods  # Should be: no
kubectl auth can-i delete pods  # Should be: no
```

## Lab: Secrets

```bash
# Deploy a secret
kubectl apply -f 04-opaque-secret.yaml           # Create a secret
kubectl get secret lab-secret -o yaml        	# See base64 encoding
kubectl get secret lab-secret -o jsonpath='{.data.db-password}' | base64 -d
# Observe: the secret is trivially decodable

# Deploy a pod consuming a secret
kubectl apply -f 05-secret-consumer-pod.yaml     # Pod consuming via both methods
kubectl exec -it secret-consumer -- sh
env | grep DB_PASSWORD                           # Env var method
cat /etc/secrets/db-password                 	# Volume mount method
```

## Network Policies

```bash
# Deploy Server and CLient Pods
kubectl apply -f 08-server-pod.yaml  	# nginx server, label: role=server
kubectl apply -f 09-client-pod.yaml  	# curl client, label: role=client
# Verify they can talk BEFORE the policy:
kubectl exec client-pod -- curl -s http://$(kubectl get pod server-pod -o jsonpath='{.status.podIP}'):80

# Apply Default Deny Policy
kubectl apply -f 06-netpol-deny-all-ingress.yaml  # Block ALL ingress to server
kubectl exec client-pod -- curl -s --max-time 3 http://<server-ip>:80
# This should TIME OUT — traffic is blocked!

# Allow Specific Traffic
kubectl apply -f 07-netpol-allow-labeled.yaml  # Allow only pods with role=client
kubectl exec client-pod -- curl -s http://<server-ip>:80
# This should WORK again

# BONUS

# Add a new pod WITHOUT the role=client label and verify it is still blocked
```

## Pod Security

```bash
# Label the default namespace with restricted enforcement
kubectl label ns default pod-security.kubernetes.io/enforce=restricted

# Non-Compliant Pod (should be REJECTED)
kubectl apply -f 13-non-compliant-pod.yaml
# Expected: Error - violates PodSecurity restricted

# Compliant Pod (should be ACCEPTED)
kubectl apply -f 12-compliant-pod.yaml
kubectl get pod compliant-pod  # Running!

kubectl label ns default pod-security.kubernetes.io/enforce-
# Remove the label to restore default behavior
```
