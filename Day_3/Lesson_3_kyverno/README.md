# Kyverno Labs
## Generate Policy Lab
In this lab we will see how kyverno generate policies can be used to create kubernetes resources in response to some action.

1. Run `make setup-generation-lab` to install the MissionDeployment CRD lesson and a cluster policyt that will process it.
2. Run `kubectl apply -f manifests/generation-lab/my-deployment.yaml` to apply the custom resource from the CRD lesson. Except now it has done something!
3. Run `kubectl describe svc my-deployment-service` to see the service our policy made
4. Run `kubectl describe configmaps my-deployment-caddy-html-config` to see our configuration file that was sourced from the crd
5. Run `kubectl get po` to see that there's now a pod in the namespace.
6. Lets take a closer look with `kubectl describe po my-deployment` to inspect the pod kyverno generated a pod for us.
7. Lets try to hit our endpoint with a `curl $(kubectl get po my-deployment -o jsonpath='{.status.hostIP}'):30080`
8. Lets clean up my-deployment by running `kubectl delete md my-deployment`
9. Lets look at that pod again with `kubectl get po`. It's gone!

### Recap
In this example we used kyverno to create a servce, configmap, and pod in response to a MissionDeployment custom resource being created. So how did it work? Kyverno read the cluster policy that told it to monitor for MissionDeployment 
CRDs and registered for an admissioin webhook with the kube-api-server. When we create our my-deployment custom resource, the API server notifed kyverno which ran our create-mission-deployments ClusterPolicy "script"
and generated kubernetes resources. When we deleted our my-deployment, kyverno responded by cleaning up the resources. This highlights the flexibility of Kyverno. It can key off of nearly anything to generate just about any resource.

As a side benefit, this hopefully gives you more insight into how operators function. Kyverno itself is an operator but also acted as a low-rent MissionDeployment operator. Please don't use Kyverno in place of a real operator as this
was definitely abusing Kyverno's ability to generat resources but this is essentially how a real MissionDeployment operator would function.

## Mutation Policy Lab
In this lab we will see how kyverno mutation policies can be used to modify resource.

1. Run `make setup-mutation-lab`. This will apply a number of kyverno mutation policies that modify pods to set best practices as well as one utility polity.
2. Run `kubectl get clusterpolicies` so see what policies got added to the cluster.
3. Our makefile also generated a certificate and added it to a configmap in the namespace. See it with `kubectl get configmap`
4. Lets apply our non-compliant-pod from the kubernetes security lecture. `kubectl apply -f manifests/mutation-lab/non-compliant-pod.yaml`
5. Now lets inspect our non-compliant-pod. `kubectl get po non-compliant-pod -o yaml` You'll notice t now has a whole lot of security practices applied to it that weren't in the definition!
```yaml
...
spec:
  securityContext:
    fsGroup: 1000
    runAsGroup: 1000
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
        - mountPath: /etc/ssl/certs
        name: etc-ssl-certs
  volumes:
    - configMap:
      defaultMode: 420
      name: ca-pemstore
    name: etc-ssl-certs
```

### Recap
In this example we saw how kyverno can mutate resources. This often is used to enforce resources to conform to best practices but we also saw how this can be used for utility Policies. Our non-compliant pod had security context rules applied to both the containers and pods. We also had a policy key off of an annotation on the pod and mutate the pod to add a volume mount of our certificate configmap into the container's cert store.

## Validating Policy Lab
1. Run `make setup-validating-lab`. This will apply a validating kyverno policy to our cluster.
2. Run `kubectl get clusterpolicies` so see what policies got added to the cluster.
3. Now lets apply a suspicious pod to our cluster `kubectl apply -f  manifests/validating-lab/suspicious-pod.yaml`. Kyverno stopped it!
```
Error from server: error when creating "manifests/validating-lab/suspicious-pod.yaml": admission webhook "validate.kyverno.svc-fail" denied the request: 

resource Pod/default/suspicious-pod was blocked due to the following policies 

disallow-host-namespaces:
  host-namespaces: 'validation error: Sharing the host namespaces is disallowed. The
    fields spec.hostNetwork, spec.hostIPC, and spec.hostPID must be unset or set to
    `false`. rule host-namespaces failed at path /spec/hostNetwork/'
disallow-host-path:
  host-path: 'validation error: HostPath volumes are forbidden. The field spec.volumes[*].hostPath
    must be unset. rule host-path failed at path /spec/volumes/0/hostPath/'
```

### Recap
Lets look at what happened. This was the pod we tried to apply.
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: suspicious-pod
  namespace: default
spec:
  hostNetwork: true
  containers:
    - name: app
      image: nginx:latest
      volumeMounts:
        - name: etc
          mountPath: /tmp/etc
  volumes:
    - name: etc
      hostPath:
        path: /etc
        type: DirectoryOrCreate
```
This pod could have done a lot of very bad things! It could have easily setup a man in the middle attack by adding certs to our trust store, added entries to /etc/hosts, and even overridden our node's firewall rules. Kyverno got notifed by the kube-api-server that this pod was about to be created, ran it's pod definition against our policies and, when it saw hostmounts and hostnetworking, it told the api-server to reject the request.
