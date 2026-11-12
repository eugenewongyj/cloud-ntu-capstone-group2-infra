#!/usr/bin/env bash
set -eo pipefail

CLUSTER_NAME="group2-capstone-cluster"
AWS_REGION="ap-southeast-1"

echo "=========================================="
echo " Starting Full GitOps & Infra Teardown"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# Helper to remove finalizers safely on macOS and Linux
strip_finalizers() {
  local kind=$1
  local ns=$2
  local ns_arg=""
  [ -n "${ns}" ] && ns_arg="-n ${ns}"

  for item in $(kubectl get "${kind}" ${ns_arg} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    kubectl patch "${kind}" "${item}" ${ns_arg} --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done
}

echo "--> [1/8] Removing Argo CD Applications and Projects..."
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  strip_finalizers "applications.argoproj.io" "argocd"
  kubectl delete applications.argoproj.io --all -n argocd --timeout=30s 2>/dev/null || true
fi
if kubectl get crd appprojects.argoproj.io >/dev/null 2>&1; then
  strip_finalizers "appprojects.argoproj.io" "argocd"
  kubectl delete appprojects.argoproj.io --all -n argocd --timeout=20s 2>/dev/null || true
fi

echo "--> [2/8] Removing Ingresses and LoadBalancer Services..."
kubectl delete ingress --all --all-namespaces --timeout=30s 2>/dev/null || true

# Strip LoadBalancer finalizer to prevent stuck ELB de-registration
for svc in $(kubectl get svc -A --field-selector spec.type=LoadBalancer -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{end}' 2>/dev/null); do
  ns="${svc%%/*}"
  name="${svc##*/}"
  echo "Releasing LoadBalancer Service ${name} in namespace ${ns}..."
  kubectl patch svc "${name}" -n "${ns}" --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
  kubectl delete svc "${name}" -n "${ns}" --timeout=30s 2>/dev/null || true
done

echo "Waiting 20 seconds for AWS Network Load Balancers to release..."
sleep 20

echo "--> [3/8] Removing Cert-Manager and ACME resources..."
for crd in challenges.acme.cert-manager.io certificates.cert-manager.io clusterissuers.cert-manager.io; do
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    strip_finalizers "${crd}" ""
    kubectl delete "${crd}" --all --all-namespaces --timeout=20s 2>/dev/null || true
  fi
done

echo "--> [4/8] Removing validating & mutating webhooks..."
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=ingress-nginx 2>/dev/null || true
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager 2>/dev/null || true
kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager 2>/dev/null || true

echo "--> [5/8] Uninstalling Helm releases..."
# Replaced jq with native awk to avoid dependency issues on Mac/Linux
helm list -A --no-headers 2>/dev/null | awk '{print $1 " -n " $2}' | while read -r release; do
  if [ -n "$release" ]; then
    helm uninstall $release 2>/dev/null || true
  fi
done

echo "--> [6/8] Purging Application Namespaces..."
for ns in monitoring cert-manager external-dns ingress-nginx trivy-system kyverno argocd logging opentelemetry-system retail-store; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    kubectl delete ns "${ns}" --timeout=20s 2>/dev/null || true
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      kubectl get ns "${ns}" -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true
    fi
  fi
done

echo "--> [7/8] Removing CRDs and StorageClass..."
# Added gp3 storage class cleanup
kubectl delete storageclass gp3 2>/dev/null || true

# Cleanup CRDs
kubectl get crd -o name 2>/dev/null | grep -E "coreos.com|cert-manager.io|argoproj.io|externaldns.k8s.io" | while read -r crd; do
  kubectl patch "${crd}" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl delete "${crd}" --timeout=15s 2>/dev/null || true
done

echo "--> [8/8] Teardown complete. Active namespaces:"
kubectl get ns