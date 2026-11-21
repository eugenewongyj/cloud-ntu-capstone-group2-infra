#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_NAME="group2-capstone-cluster"
AWS_REGION="ap-southeast-1"
REPO_URL="https://github.com/eugenewongyj/cloud-ntu-capstone-group2-infra.git"
VALUES_FILE="bootstrap/common-infra/argocd-values.yaml"
NODECLASS_FILE="bootstrap/common-infra/nodeclass.yaml"
NODEPOOL_FILE="bootstrap/common-infra/nodepool.yaml"


echo "=========================================="
echo " Starting GitOps Cluster Bootstrap"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/7] Updating kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# 2. Apply EKS Auto Mode t3.medium NodePool BEFORE ArgoCD
echo "--> [2/7] Applying EKS Auto Mode t3.medium NodePool..."
if [ -f "${NODEPOOL_FILE}" ]; then
  kubectl apply -f "${NODECLASS_FILE}"
  kubectl apply -f "${NODEPOOL_FILE}"
  kubectl wait --for=condition=Ready nodeclass/default --timeout=60s || true
  kubectl wait --for=condition=Ready nodepool/t3-medium-pool --timeout=60s || true
else
  echo "Warning: ${NODEPOOL_FILE} not found; relying on built-in EKS Auto Mode NodePools."
fi

# # 3. Deploy default gp3 StorageClass & Pre-create core namespaces
# echo "--> [3/7] Applying gp3 StorageClass and pre-creating argocd namespace..."
# if [ -f "bootstrap/common-infra/gp3.yaml" ]; then
#   kubectl apply -f bootstrap/common-infra/gp3.yaml
# fi

for ns in argocd; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

# 4. Bootstrap Argo CD via Helm
echo "--> [4/7] Deploying Argo CD Helm chart with custom values..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo "Waiting for Argo CD API server deployment rollout..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

# 5. Apply AppProjects
echo "--> [5/7] Applying Argo CD AppProjects..."
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml
kubectl apply -f sec/projects/sec-project.yaml

# 6. GitOps Handoff (App-of-Apps Root Deployments)
echo "--> [6/7] Applying Root GitOps Applications..."
kubectl apply -f bootstrap/root.yaml

# 7. Print Credentials and Access URL
echo "--> [7/7] Retrieving initial admin credentials..."
ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

echo "=========================================="
echo " GitOps bootstrap complete!"
echo " Argo CD is now orchestrating Infra, SRE, Sec, and Applications."
echo " URL:      https://group2-capstone-argocd.sctp-sandbox.com"
echo " Username: admin"
if [ -n "${ADMIN_PWD}" ]; then
  echo " Password: ${ADMIN_PWD}"
else
  echo " Password: (initial-admin-secret removed or password already changed)"
fi
echo "=========================================="