#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_NAME="group2-capstone-cluster"
AWS_REGION="ap-southeast-1"
VALUES_FILE="bootstrap/common-infra/argocd-values.yaml"
NODEPOOL_DIR="bootstrap/common-infra/nodepool"
PRIORITY_CLASSES_FILE="bootstrap/common-infra/priority-classes.yaml"

echo "=========================================="
echo " Starting GitOps Cluster Bootstrap"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/8] Updating kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# 2. Apply EKS Auto Mode Tiered t3.medium NodePools BEFORE ArgoCD
echo "--> [2/8] Applying EKS Auto Mode tiered t3.medium NodePools..."
if [ -d "${NODEPOOL_DIR}" ]; then
  kubectl apply -f "${NODEPOOL_DIR}/logging-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/monitoring-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/security-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/platform-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/apps-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/apps-staging-nodepool.yaml"
  kubectl apply -f "${NODEPOOL_DIR}/system-nodepool.yaml"

  kubectl wait --for=condition=Ready nodeclass/default --timeout=60s || true
  for np in \
    t3-medium-logging-nodepool \
    t3-medium-monitoring-nodepool \
    t3-medium-security-nodepool \
    t3-medium-platform-nodepool \
    t3-medium-apps-nodepool \
    t3-medium-system-nodepool \
    t3-medium-apps-staging-nodepool; do
    kubectl wait --for=condition=Ready "nodepool/${np}" --timeout=60s || true
  done
else
  echo "Warning: ${NODEPOOL_DIR} not found; relying on built-in EKS Auto Mode NodePools."
fi

# 3. Apply Cluster PriorityClasses BEFORE ArgoCD & Workloads
echo "--> [3/8] Applying Cluster PriorityClasses..."
if [ -f "${PRIORITY_CLASSES_FILE}" ]; then
  kubectl apply -f "${PRIORITY_CLASSES_FILE}"
  kubectl get priorityclasses platform-critical prod-critical staging-low
else
  echo "Warning: ${PRIORITY_CLASSES_FILE} not found; skipping PriorityClass creation."
fi

# 4. Pre-create core namespaces
echo "--> [4/8] Applying pre-creating core namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 5. Bootstrap Argo CD via Helm
echo "--> [5/8] Deploying Argo CD Helm chart with custom values..."
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

# 6. Apply AppProjects
echo "--> [6/8] Applying Argo CD AppProjects..."
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml
kubectl apply -f app-staging/projects/app-staging-project.yaml
kubectl apply -f sec/projects/sec-project.yaml

# 7. GitOps Handoff (App-of-Apps Root Deployments)
echo "--> [7/8] Applying Root GitOps Applications..."
kubectl apply -f bootstrap/root.yaml

# 8. Print Credentials and Access URL
echo "--> [8/8] Retrieving initial admin credentials..."
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