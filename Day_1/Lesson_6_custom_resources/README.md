# Custom Resources Labs
## LAB 1 - K9s? Kubectl? Real Engineers use Curl!
1. Run `make setup`
2. Start a proxy in the background.
```shell
kubectl proxy 8001 &
```
3. Check out pods in the kube-system namespace.
```shell
curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/ | head -n 20
```
4. Look at the names of pods 
```shell
curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods | jq '.items[].metadata.name'
```
5. Inspect the api-server definition of the kube api server. 
```shell
curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/kube-apiserver | jq
```
6. Check on the api server status 
```shell
curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/kube-apiserver/status | jq
```

## LAB 2 - Birds and Bees: How k8s Resources Are Born
1. Run `make setup`
2. Apply the MissionDeployment CRD to the cluster with 
```shell
kubectl apply -f manifests/MissionDeployment.yaml
```
3. Apply a MissionDeployment instance to the cluster with 
```shell
kubectl apply -f manifests/my-deployment.yaml
```
4. List all MissionDeployments 
```shell
kubectl get md -A
```
5. Inspect our MissionDeployment instance 
```shell
kubectl describe md -n default my-deployment
```