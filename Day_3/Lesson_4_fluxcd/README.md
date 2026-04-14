# Fluxcd Labs

## Flux Gitrepo Lab
We are going to see how flux installs from a gitrepo in this lab.
1. Run `make setup-flux` to install flux into your cluster.
2. Run `kubectl apply -f manifests/gitrepo.yaml`. This will create a flux Gitrepository object that points back to this project on github
   and a kustomization that points to `./Day_3/Lesson_4_flux_argocd/manifests/git-kustomization` in the repo.
```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
name: git-example
namespace: default
spec:
interval: 5m
url: https://github.com/chameleoncg/k8s-training-student-resources
ref:
branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
name: git-example
namespace: default
spec:
interval: 10m
targetNamespace: default
sourceRef:
kind: GitRepository
name: git-example
path: "./Day_3/Lesson_4_flux_argocd/manifests/git-kustomization"
prune: true
timeout: 1m
```
3. Run `kubectl get po -n flux-system` and get the name of the source controller.
4. Run `kubectl -n flux-system exec -it source-controller-7cd5f69dc9-<id of source controller> -- ls -la /data/gitrepository/default/git-example`. This is showing us the content of the source controller file system down `/data/gitrepository/default/git-example`. You will notice that default is the namespace that our gitrepo was deployed into and the name of the gitrepo was `git-example`. You will also notice that the name of the tarball in that diretory corresponds to the sha of the branch it is pointing to. That is because the flux source controller has essentially cloned the gitrepo.
5. Run a `kubectl get po` and notice that obscurity-pod from the day 0 lecture is present

## Flux Helmrepo Lab
We are going to see how flux installs from a helm repository in this lab.
1. Run `make setup-flux` to install flux into your cluster.
2. Run `kubectl apply -f manifests/helmvalues.yaml`. This will create a configmap in the cluster that we are going to tell Flux to reference when doing the helm install into the cluster. There are a number of ways you can pass values into a Flux `helmRelease` but configmaps are often a very convenient method for doing this. Here's the contents of helmvalues
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: helmvalues
  namespace: default
data:
  values.yaml: |-
    replicaCount: 2
    serviceAccount:
      enabed: true
```
3. Now lets make a helmrepo and helmrelease for podinfo. `kubectl apply -f manifests/helmrepo.yaml`
```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
 name: podinfo
 namespace: default
spec:
 interval: 15m
 url: https://stefanprodan.github.io/podinfo
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  interval: 15m
  timeout: 5m
  chart:
    spec:
      chart: podinfo
      version: '6.5.*'
      sourceRef:
        kind: HelmRepository
        name: podinfo
      interval: 5m
  releaseName: podinfo
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  test:
    enable: true
  driftDetection:
    mode: enabled
    ignore:
      - paths: ["/spec/replicas"]
        target:
          kind: Deployment
  valuesFrom:
    - kind: ConfigMap
      name: helmvalues
```
4. We can see the install state of our helm install by running `kubectl get helmrepo` and `kubectl get helmrelease`
5. Now lets look at the source controller and see how it is handling the helmrelease. Run `kubectl get po -n flux-system` and get the name of the source controller.
6. Run `kubectl -n flux-system exec -it source-controller-7cd5f69dc9-<id of source controller> -- ls -la /data/helmrepository/default/podinfo`. Similar to the gitrepo lab, we can see the source controller has pulled down the index yaml (helm index file). This is exactly what happens when you run `helm repo add podinfo https://stefanprodan.github.io/podinfo` using the helmcli. The source controller is really doing nothing different than what a user would do when installing a chart or manifest. It grabs the source and installs it into the cluster.
7. Run `make teardown` to clean up the cluster.

## Flux Gitops Lab
We are going to put the last two labs together in a simple gitops example.
1. Run `make setup-flux` to install flux into your cluster.
2. Now lets bootstrap the gitops example into our cluster. `kubectl apply -f kubectl apply -f manifests/gitops-example/bootstrap.yaml`