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

## Deployment 5

## Deployment 6

# LAB3

## Deployment 7

# LAB4

## Deployment 8

