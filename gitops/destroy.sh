#!/usr/bin/env bash
set -eo pipefail

CLUSTER_NAME="group2-tk-cluster"
AWS_REGION="ap-southeast-1"

echo "=========================================="
echo " Starting Full GitOps & Infra Teardown"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/9] Ensuring cluster access..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# Helper function to remove finalizers from stuck resources
remove_finalizers() {
  local kind=$1
  local ns=$2
  echo "Stripping finalizers from ${kind} in namespace${ns}..."
  kubectl get "${kind}" -n "${ns}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | xargs -r -n1 -I {} \
    kubectl patch "${kind}" {} -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
}

# 2. Delete Argo CD Root and Child Applications
echo "--> [2/9] Deleting Argo CD Applications..."
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  # Strip finalizers to prevent hanging deletion if Git repo is unreachable
  remove_finalizers "applications.argoproj.io" "argocd"
  kubectl delete applications.argoproj.io --all -n argocd --cascade=foreground --timeout=60s || true
  # Force remove any remaining applications
  remove_finalizers "applications.argoproj.io" "argocd"
  kubectl delete applications.argoproj.io --all -n argocd --force --grace-period=0 2>/dev/null || true
fi

# 3. Clean Ingresses & Services to trigger AWS NLB / ELB deprovisioning
echo "--> [3/9] Removing Ingresses and LoadBalancer Services..."
kubectl delete ingress --all --all-namespaces --timeout=60s || true
kubectl delete svc -n ingress-nginx --all --timeout=60s || true
kubectl delete svc -n kube-system -l k8s-app=cilium-envoy --timeout=60s || true

echo "Waiting 30 seconds for AWS Network Load Balancers to release..."
sleep 30

# 4. Uninstall Helm Releases
echo "--> [4/9] Uninstalling Helm releases..."
helm list -A -q | while read -r release; do
  ns=$(helm list -A --filter "^${release}$" -o json | jq -r '.[0].namespace')
  echo "Uninstalling helm release '${release}' in namespace '${ns}'..."
  helm uninstall "${release}" -n "${ns}" || true
done

# 5. Remove cert-manager and ACME Resources
echo "--> [5/9] Cleaning Cert-Manager and ACME resources..."
if kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
  kubectl delete clusterissuer --all --timeout=30s || true
fi
if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  kubectl delete certificate --all --all-namespaces --timeout=30s || true
fi

# 6. Delete Application Namespaces
echo "--> [6/9] Deleting namespaces..."
for ns in monitoring cert-manager external-dns ingress-nginx retail-store argocd; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    echo "Deleting namespace: ${ns}..."
    kubectl delete ns "${ns}" --timeout=45s || true
    # If stuck in Terminating due to finalizers:
    if kubectl get ns "${ns}" 2>/dev/null | grep -q "Terminating"; then
      echo "Namespace ${ns} is stuck in Terminating. Removing finalizer..."
      kubectl get ns "${ns}" -o json \
        | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
        | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - || true
    fi
  fi
done

# 7. Remove Prometheus Operator & Cert-Manager CRDs
echo "--> [7/9] Removing Custom Resource Definitions (CRDs)..."
kubectl get crd -o name 2>/dev/null | grep -E "coreos.com|cert-manager.io|argoproj.io|externaldns.k8s.io" | while read -r crd; do
  echo "Deleting CRD: ${crd}..."
  kubectl delete "${crd}" --timeout=20s || true
done

# 8. Clean AppProjects and Git Repository Secrets
echo "--> [8/9] Cleaning residual cluster resources..."
if kubectl get crd appprojects.argoproj.io >/dev/null 2>&1; then
  kubectl delete appprojects.argoproj.io --all -n argocd --timeout=20s || true
fi

# 9. Clear Route 53 TXT registry records (Optional cleanup for ExternalDNS)
echo "--> [9/9] Verifying cluster state..."
echo "Remaining Namespaces:"
kubectl get ns
echo "Remaining Ingresses:"
kubectl get ingress --all-namespaces || true

echo "=========================================="
echo " Cluster clean! Ready for fresh bootstrap."
echo " Run ./init.sh to rebuild the platform."
echo "=========================================="