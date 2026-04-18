Recommend not reviewing this until you have attempted all of the labs.

The commands shown in the "solutions" are `kubectl` commands, but
corresponding `k9s` commands could be used instead.

# LAB1

## Deployment 1

In this deployment, there is a typo in the image for the container name
used for the deployment. 

To see this mistake, run `kubectl describe pod -n debugging <pod-name>`

You will see an error similar to:

```
  Warning  Failed     2m56s (x5 over 5m51s)  kubelet            spec.containers{pause}: Failed to pull image "registry.kBs.io/pause:3.9": failed to pull and unpack image "registry.kBs.io/pause:3.9": failed to resolve reference "registry.kBs.io/pause:3.9": failed to do request: Head "https://registry.kBs.io/v2/pause/manifests/3.9": remote error: tls: unrecognized name
```

Note that there is an image pull error. Look closely at the image and recognize
there is likely a typo `Failed to pull image "registry.kBs.io/pause:3.9"`

Edit the deployment1.yaml file to have the image name of
`registry.k8s.io/pause:3.9` replacing the *B* with an *8*.
Wait for the deployment to restart the pod, and watch it pull successfully.

Remember that you can reapply releases with `kubectl apply -f <deploy_file>`

## Deployment 2

In this deployment, the image is in a private registry that cannot be pulled
from in the current setup. To get around this, private images can be accessed
by setting a secret and adding a specific reference to it to your deployment.

You can see the failed image pull by running a describe
`kubectl describe pod -n debugging <pod-name>`

You will see an error similar to:

```
  Warning  Failed     12m (x5 over 14m)     kubelet            spec.containers{app}: Failed to pull image "ghcr.io/jsmith-clarityinnovates/python:1.0.0": failed to pull and unpack image "ghcr.io/jsmith-clarityinnovates/python:1.0.0": failed to resolve reference "ghcr.io/jsmith-clarityinnovates/python:1.0.0": failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Ajsmith-clarityinnovates%2Fpython%3Apull&service=ghcr.io: 401 Unauthorized
```

Note the failure for a `401 Unauthorized` reason.

You can then check the deployment2.yaml file to see if the required secret
config is present. Open the file and look for a block like

```
  imagePullSecrets:
  - name: <secret_name>
```

You'll notice that no such configuration is present. You can then see if
there is a secret present already that might have the required auth in it.

`kubectl get secrets -n debugging`
`kubectl describe secret -n debugging private-registry-creds` or
`kubectl edit secret -n debugging private-registry-creds`

You find that there does appear to be a valid secret, so you can attempt
to update the deployment to use it. 

Add this to the deployment file. Update it from

```
        app: deployment2
    spec:
      containers:
        - name: app
          image: ghcr.io/jsmith-clarityinnovates/python:1.0.0
```

to

```
        app: deployment2
    spec:
      containers:
        - name: app
          image: ghcr.io/jsmith-clarityinnovates/python:1.0.0
      imagePullSecrets:
        - name: private-registry-cred
```

After doing this, you'll notice that the deployment is still failing for a 401.

This is usually indicative that the creds you're using are incorrect, and
you would have to reach out to the owner of the repository or the person that
gave you the credentials for updated credentials.

## Deployment 3

Deployment three is rather unique in that if you start just by looking for
pods, you'll not see deployment three.

`kubectl get pods -n debugging`

```
NAME                                  READY   STATUS             RESTARTS         AGE
deployment1-5c958c5b79-pxq4s          1/1     Running            0                16m
deployment2-6495bcf979-7p8fk          0/1     ImagePullBackOff   0                27m
deployment4-77d498bf4f-jdr27          0/1     Error              10 (6m16s ago)   27m
...
```

To gather information about what is going wrong here, walk through the
describing deployment and then replicaset.

`kubectl describe deployment -n debugging deployment3`

```
  ReplicaFailure   True    FailedCreate
  Progressing      False   ProgressDeadlineExceeded
OldReplicaSets:    <none>
NewReplicaSet:     deployment3-7ddd5f85b5 (0/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  29m   deployment-controller  Scaled up replica set deployment3-7ddd5f85b5 from 0 to 1
```

Note, not major errors in the Event log for the deployment.

`kubectl describe replicaset -n debugging deployment3-######`

Note the errors in the event log.

```
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  FailedCreate  31m   replicaset-controller  Error creating: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/debugging/deployment3-7ddd5f85b5-r4jq4 was blocked due to the following policies

require-guard-for-policy-target:
  require-guard-label: 'validation error: guard: training is required. rule require-guard-label
    failed at path /metadata/labels/guard/'
```

This suggests to take a look at the Kyverno policies.

`kubectl get kyverno -A`

Shows all kyverno policies; you will see one clusterpolicy that is applied to
this cluster. You can gain more information by describing this policy.

`kubectl describe clusterpolicies  require-guard-for-policy-target`

See the rule at the top.

```
  Rules:
    Match:
      Any:
        Resources:
          Kinds:
            Pod
    Name:  require-guard-label
    Preconditions:
      All:
        Key:                   {{ request.object.metadata.labels.training || '' }}
        Operator:              Equals
        Value:                 policy-target
    Skip Background Requests:  true
    Validate:
      Allow Existing Violations:  true
      Message:                    guard: training is required
      Pattern:
        Metadata:
          Labels:
            Guard:            training
```

This requires that there be a label called `guard: training` against any pod
that has the label `training=policy-target`.

From describing the pod earlier, we can see that this deployment would deploy
pods with that label.

```
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=deployment3
           training=policy-target
  Containers:
```

To fix, update the deployment file to add the appropriate label.

```
  template:
    metadata:
      labels:
        app: deployment3
        training: policy-target
        guard: training
    spec:
```

And reapply it to your cluster.

# LAB2

## Deployment 4

In this deployment, the pod appears to be in a CrashLoopBackOff, as
recommended, you should start with just a describe and see if there's anything
interesting there.

`kubectl describe pod -n debugging <pod>`

Unfortunately, nothing shows up from the describe that is overly useful.

```
  Type     Reason   Age                    From     Message
  ----     ------   ----                   ----     -------
  Normal   Pulled   4m10s (x243 over 20h)  kubelet  spec.containers{app}: Container image "debugging/distro-python:1.0.0" already present on machine and can be accessed by the pod
  Normal   Created  4m10s (x243 over 20h)  kubelet  spec.containers{app}: Container created
  Warning  BackOff  4m9s (x1047 over 20h)  kubelet  spec.containers{app}: Back-off restarting failed container app in pod deployment4-77d498bf4f-jdr27_debugging(dea3e6cd-66b8-47aa-ac23-3f828824095b)
```

Next, you should likely run logs against the pod

`kubectl logs -n debugging deployment4-77d498bf4f-jdr27`

Revealing

```
Defaulting to default logging, to increase logging, set LOG_LEVEL to DEBUG
LOG_LEVEL: None
```

Seeing this, the logs suggest adding an environment variable for "LOG_LEVEL"
and set it to DEBUG. To do that, edit the deployment and add the following.

```
    spec:
      volumes:
      containers:
        - name: app
          image: debugging/distro-python:1.0.0
          imagePullPolicy: IfNotPresent
          env:
            - name: LOG_LEVEL
              value: DEBUG
```

After adding the environment variable, rechecking the logs shows the following.

```
LOG_LEVEL: DEBUG
Missing or inccorect value for required variable REQUIRED_ENV. Set it to "true".
```

Seeing this, the logs suggest adding an environment variable called
"REQUIRED_ENV" and setting it to "true". Do this similar to the above,
after doing this, the pod runs successfully.

## Deployment 5

Similar to deployment 4, this deployment is in a CrashLoopBackOff. Describing
the deployment does not reveal anything useful.

Looking at the logs for the pod, so the following:

```
During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<string>", line 5, in <module>
  File "/usr/local/lib/python3.11/urllib/request.py", line 216, in urlopen
    return opener.open(url, data, timeout)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/urllib/request.py", line 519, in open
    response = self._open(req, data)
               ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/urllib/request.py", line 536, in _open
    result = self._call_chain(self.handle_open, protocol, protocol +
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/urllib/request.py", line 496, in _call_chain
    result = func(*args)
             ^^^^^^^^^^^
  File "/usr/local/lib/python3.11/urllib/request.py", line 1391, in https_open
    return self.do_open(http.client.HTTPSConnection, req,
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/urllib/request.py", line 1351, in do_open
    raise URLError(err)
urllib.error.URLError: <urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate (_ssl.c:1016)>
```

We can see a cert error here, if we describe the deployment we can get
a better idea of what it is trying to talk to.

```
    Command:
      python
      -c
      import time
      import urllib.request

      while True:
        with urllib.request.urlopen(
            "https://service5.debugging.svc.cluster.local",
            timeout=5,
        ) as response:
            print(response.read().decode())

        time.sleep(8)

    Environment:
```

Here we can see it is trying to connect to services5 in the debugging
namespace. If we describe the service5 deployment, we can see it is using
a secret, service5-tls, mounted into the pod to act as its certificate.

```
    Command:
      python
      -c
      import http.server
      import ssl

      class Handler(http.server.BaseHTTPRequestHandler):
          def do_GET(self):
              self.send_response(200)
              self.end_headers()
              self.wfile.write(b"ok\n")

      httpd = http.server.ThreadingHTTPServer(("0.0.0.0", 8443), Handler)
      context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
      context.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
      httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
      httpd.serve_forever()

    Environment:  <none>
    Mounts:
      /tls from tls (ro)
  Volumes:
   tls:
    Type:          Secret (a volume populated by a Secret)
    SecretName:    service5-tls
    Optional:      false
```

If we grab the secrets, we can see a deployment5-ca, which we can guess
may be the CA that signed this certificate. If you don't want to make this
assumption, you could use openssl to verify this.

To add this CA to deployment5, it is a secret, so we can mount that secret
in as a file. To do that, edit your deployment5.yaml file.

```
...
        volumeMounts:
        - mountPath: /etc/ssl/certs/ca-bundle.crt
          name: ca-bundle
          readOnly: true
          subPath: ca-certificates.crt
...
      volumes:
      - name: ca-bundle
        secret:
          defaultMode: 292
          secretName: deployment5-ca
...
```

You must add a volume under "volumes" matching the secret, and then mount
that volume into the container. Note, that because I mounted into an existing
directory and I just want to mount a specific file, it's important to use
"subPath", which will result in the "ca-certificates.crt" value from the
secret being placed at the file "/etc/ssl/certs/ca-bundle.crt"

After the CA is inside the container, you need to have your software use it,
to do this, update the python to add the SSL context.

```
          command:
            - python
            - -c
            - |
              import time
              import urllib.request

              ctx = ssl.create_default_context(cafile="/etc/ssl/certs/ca-bundle.crt")

              while True:
                with urllib.request.urlopen(
                    "https://service5.debugging.svc.cluster.local",
                    timeout=5,
                    context=ctx,
                ) as response:
                    print(response.read().decode())

                time.sleep(8)
```

After that, the deployment will restart and you should start seeing "ok" in the
logs.

## Deployment 6

Unlike deployment 4 and 5, this pod appears to be running successfully, or at
least, it has the "Running" status. Describing the pod does not reveal anything
interesting, however, the logs for the pod shows.

```
Writing logs to /var/log
Error in appliation, exiting
```

This log suggest the application is likely not running correctly. If this were
a web application, it would be good to check the web UI; but this is not, so
we will just have to trust the logs. The logs suggest reading a log in
/var/log.

To view the file system of the container, exec into the container.

`kubectl exec -it -n debugging <pod> -- /bin/bash`

Upon doing so, we see the following files in /var/log/

```
root@deployment6-5884bb9dc5-7cxbp:/app# cd /var/log
root@deployment6-5884bb9dc5-7cxbp:/var/log# ls
alternatives.log  apt  btmp  dpkg.log  lastlog  log.txt  wtmp
```

For those familiar with linux, you probably notice a stand out "log.txt" file.

cat'ing that file shows the following

```
root@deployment6-5884bb9dc5-7cxbp:/var/log# cat log.txt
Missing or incorrect value for required variable REQUIRED_ENV2. Set it to "true".
```

Similar to Lab 4, this suggested a missing env variable REQUIRED_ENV2.
Upon doing that, the pod stays in a Running status, now with no errors in the
log output.

# LAB3

## Deployment 7

For deployment7, we can see the pod is stuck in an Init:0/1 state, when getting
pods in the cluster.

This status tells us there is an init container that is not completing.

```
deployment6-5f994d95c8-xhbgg          1/1     Running            144 (5m43s ago)   24h
deployment7-599b5f769f-2lbt9          0/1     Init:0/1           0                 45h
deployment8-79897db4b6-96x5w          0/1     CrashLoopBackOff   530 (4m29s ago)   45h
```

If we describe the pod we something similar, and Init Container that is in the
status "Running." 

If we try to get the logs of the pod, you will see an error if you just run
this command.

`kubectl logs -n debugging <pod>`

```
Defaulted container "app" out of: app, wait-for-health (init)
Error from server (BadRequest): container "app" in pod "deployment7-599b5f769f-2lbt9" is waiting to start: PodInitializing
```

This is because Init containers are not shown by default when running kubectl
logs, you have to manually specify the container with the -c flag. 

`kubectl logs -n debugging deployment7-599b5f769f-2lbt9 -c wait-for-health`

You can also use k9s, step into the pod, and find the specific container to
look at the logs. This is also required if a pod has multiple containers in it.

Looking at the init container logs, we see

```
Health check failed, retrying in 5s...
Health check failed, retrying in 5s...
Health check failed, retrying in 5s...
```

If we describe the deployment again, we can more closely inspect what the Init
container is trying to do.

```
  Init Containers:
   wait-for-health:
    Image:      busybox
    Port:       <none>
    Host Port:  <none>
    Command:
      sh
      -c
      echo "Waiting for healthcheck-server..."
      echo "Attempting wget against http://healthcheck-server:8080"
      until wget -qO- http://healthcheck-server:8080 > /dev/null 2>&1; do
        echo "Health check failed, retrying in 5s..."
        sleep 5
      done
      echo "Health check passed. Starting main container."
```

It appears the Init Container is trying to connect to a service at
"healthcheck-server" on port 8080, let's see if that service exists.

`kubectl get service -n debugging`

```
NAME                 TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
deployment7          LoadBalancer   10.96.220.213   <pending>     80:32697/TCP   45h
healthcheck-server   ClusterIP      10.96.177.219   <none>        8080/TCP       45h
service5             ClusterIP      10.96.149.218   <none>        443/TCP        45h
```

We can see there is a service by that name in the debugging namespace.
It appears to be listening port 8080. For now, let's assume that service
is not misbehaving and would respond to a request by deployment7. What else
could be causing our traffic to not be able to arrive at that service. Since
we're on a single physical node running kind, and these services are running
on the same k8s node, there's unlikely something physical or even at the OS
level is preventing the traffic. It's not impossible, but less likely. Instead,
a network policy could be prevent this traffic. Let's see if there are any
network policies in the debugging namespace.

`kubectl get networkpolicies -n debugging`

```
NAME                POD-SELECTOR             AGE
block-deployment7   app=healthcheck-server   45h
```

Lets describe this netpol.

```
Spec:
  PodSelector:     app=healthcheck-server
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
```

It appears that this netpol is blocking all ingress traffic. If I simply delete
this netpol, the service would likely start working. But let's see if we can
be more granular with what traffic we allow through. Let's edit the deployment
to allow traffic on 8080 only. 

When editing the deployment7 file, we can see an explicitly empty ingress list,
blocking all traffic. If we change the ingress block to:

```
  ingress:
  - ports:
    - protocol: TCP
      port: 8080
```

It will allow 8080 traffic through. Upon applying this change, eventually the
healthcheck in the init container will pass, and the pod will deploy
successfully.

# LAB4

## Deployment 8

