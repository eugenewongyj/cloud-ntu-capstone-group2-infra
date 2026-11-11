#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_NAME="group2-capstone-cluster"
AWS_REGION="ap-southeast-1"
REPO_URL="https://github.com/eugenewongyj/cloud-ntu-capstone-group2-infra.git"
# AWS_SECRET_ID="group2-capstone/argocd/github-pat"
VALUES_FILE="bootstrap/common-infra/argocd-values.yaml"

echo "=========================================="
echo " Starting GitOps Cluster Bootstrap"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/9] Updating kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# 2. Deploy default gp3 StorageClass & Pre-create core namespaces
# echo "--> [2/9] Applying gp3 StorageClass and pre-creating namespaces..."
# kubectl apply -f bootstrap/common-infra/gp3.yaml

for ns in argocd ingress-nginx cert-manager external-dns monitoring logging trivy-system kyverno; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

# # 3. Pre-install Prometheus Operator CRDs
# echo "--> [3/9] Applying Prometheus Operator CRDs via Server-Side Apply..."
# kubectl apply --server-side \
#   -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml \
#   -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml \
#   -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml \
#   -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml

# 4. Bootstrap Argo CD via Helm
echo "--> [4/9] Deploying Argo CD Helm chart with custom values..."
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

# # 5. Fetch GitHub PAT from AWS Secrets Manager & Register Repo Secret
# echo "--> [5/9] Configuring Git repository credentials in Argo CD..."
# if aws secretsmanager describe-secret --secret-id "${AWS_SECRET_ID}" --region "${AWS_REGION}" >/dev/null 2>&1; then
#   GITHUB_PAT=$(aws secretsmanager get-secret-value --secret-id "${AWS_SECRET_ID}" --region "${AWS_REGION}" --query "SecretString" --output text)
#   kubectl create secret generic repo-peh3-infra -n argocd \
#     --from-literal=type=git \
#     --from-literal=url="${REPO_URL}" \
#     --from-literal=password="${GITHUB_PAT}" \
#     --from-literal=username="peh3" \
#     --dry-run=client -o yaml | kubectl apply -f -
#   kubectl label secret repo-peh3-infra -n argocd "argocd.argoproj.io/secret-type=repository" --overwrite
#   echo "Repository credentials registered."
# else
#   echo "Notice: Secret '${AWS_SECRET_ID}' not found in AWS Secrets Manager; relying on public repo access."
# fi

# 6. Apply AppProjects (with destination ingress-nginx whitelisted)
echo "--> [6/9] Applying Argo CD AppProjects..."
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml
kubectl apply -f sec/projects/sec-project.yaml 

# 7. GitOps Handoff (App-of-Apps Root Deployments)
echo "--> [7/9] Applying Root GitOps Applications..."
kubectl apply -f bootstrap/root.yaml

# 8. Wait for AWS NLB Allocation and Route 53 Propagation
# echo "--> [8/9] Waiting for Ingress NGINX controller and AWS NLB hostname..."
# echo "Waiting for ingress-nginx-controller Service to be created..."
# for i in {1..36}; do
#   kubectl get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1 && break
#   [ "$i" -eq 36 ] && { echo "ERROR: ingress-nginx never deployed"; exit 1; }
#   sleep 5
# done

# echo "Waiting for AWS NLB hostname assignment..."
# NLB_HOSTNAME=""
# for i in {1..36}; do
#   NLB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
#   if [ -n "${NLB_HOSTNAME}" ]; then
#     break
#   fi
#   echo "Waiting for AWS NLB... ($((i * 5))s)"
#   sleep 5
# done

# if [ -n "${NLB_HOSTNAME}" ]; then
#   echo "AWS NLB Hostname active: ${NLB_HOSTNAME}"
# else
#   echo "Warning: NLB hostname assignment timed out; check AWS Load Balancer Controller logs in kube-system."
# fi

# echo "Waiting for Argo CD Ingress to be created and populated..."
# for i in {1..36}; do
#   if kubectl get ingress argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | grep -q .; then
#     break
#   fi
#   echo "Waiting for Argo CD Ingress... ($((i * 5))s)"
#   sleep 5
# done

# echo "Waiting for Argo CD Ingress hostname..."
# OK=0
# for i in {1..36}; do
#   HOST=$(kubectl get ingress argocd-server -n argocd \
#           -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
#   if [ -n "${HOST}" ]; then OK=1; break; fi
#   echo "Waiting for Argo CD Ingress... ($((i * 5))s)"
#   sleep 5
# done
# [ "$OK" -eq 1 ] || { echo "ERROR: Argo CD Ingress never got a hostname"; exit 1; }


# 9. Print Credentials and Access URL
echo "--> [9/9] Retrieving initial admin credentials..."
ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

echo "=========================================="
echo " GitOps bootstrap complete!"
echo " Argo CD is now orchestrating Infra, SRE, and Applications."
echo " URL:      https://group2-capstone-argocd.sctp-sandbox.com"
echo " Username: admin"
if [ -n "${ADMIN_PWD}" ]; then
  echo " Password: ${ADMIN_PWD}"
else
  echo " Password: (initial-admin-secret removed or password already changed)"
fi
echo "=========================================="