#!/bin/bash

# Exit on error
set -e

echo "--- 1. Patching Longhorn for 2-Node Environment ---"
# Sets replica count to 2 and allows over-provisioning for KiND/Lab environments
kubectl -n longhorn-system patch settings.longhorn.io default-replica-count --type merge -p '{"value": "2"}'
kubectl -n longhorn-system patch settings.longhorn.io storage-over-provisioning-interface --type merge -p '{"value": "200"}'
echo "✅ Longhorn settings updated."

echo "--- 2. Creating Persistent Volume Claim (PVC) ---"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-verify-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

echo "--- 3. Deploying Test Pod (The Consumer) ---"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-checker
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: longhorn-verify-pvc
EOF

echo "--- 4. Waiting for Volume Binding ---"
# This waits up to 2 minutes for the PVC to hit the "Bound" state
echo "Waiting for PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/longhorn-verify-pvc --timeout=120s

echo "--- 5. Final Health Check ---"
kubectl get pvc longhorn-verify-pvc
kubectl get pod storage-checker

echo "--------------------------------------------------------"
echo "VALIDATION COMPLETE"
echo "Your PVC is BOUND and your Pod is RUNNING."
echo "--------------------------------------------------------"