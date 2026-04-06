# Custom Resources Labs
## LAB 1 - K9s? Kubectl? Real Engineers use Curl!
1. Run `kubectl proxy 8001 &` to start a proxy
2. Check out pods in the kube-system namespace. `curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/ | head -n 20`
3. Look at the names of pods `curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods | jq '.items[].metadata.name'`
4. Inspect the api-server definition of the kube api server. `curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/kube-apiserver | jq`
5. Check on the api server status `curl -s http://localhost:8001/api/v1/namespaces/kube-system/pods/kube-apiserver/status | jq`

## LAB 2 - Birds and Bees: How k8s Resources Are Born
1. Apply the MissionDeployment CRD to the cluster with `kubectl apply -f manifests/MissionDeployment.yaml`
2. Apply a MissionDeployment instance to the cluster with `kubectl apply -f manifests/my-deployment.yaml`
3. List all MissionDeployments `kubectl get md -A`
4. Inspect our MissionDeployment instance `kubectl describe md -n default my-deployment`