#!/usr/bin/env bash
set -eo pipefail

CLUSTER_NAME="group2-capstone-cluster"
AWS_REGION="ap-southeast-1"

TARGET_NAMESPACES=(
  "retail-store"
  "opentelemetry-system"
  "logging"
  "monitoring"
  "trivy-system"
  "kyverno"
  "ingress-nginx"
  "external-dns"
  "cert-manager"
  "argocd"
)

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

  if [ -z "${ns}" ]; then
    kubectl get "${kind}" -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | while read -r item_ns item_name; do
      if [ -n "${item_name}" ]; then
        if [ -n "${item_ns}" ]; then
          kubectl patch "${kind}" "${item_name}" -n "${item_ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        else
          kubectl patch "${kind}" "${item_name}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        fi
      fi
    done
  else
    for item in $(kubectl get "${kind}" ${ns_arg} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
      kubectl patch "${kind}" "${item}" ${ns_arg} --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    done
  fi
}

echo "--> [1/9] Removing Argo CD Applications and Projects..."
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  for app in $(kubectl get applications.argoproj.io -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    kubectl patch applications.argoproj.io "${app}" -n argocd --type=merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true
  done
  strip_finalizers "applications.argoproj.io" "argocd"
  kubectl delete applications.argoproj.io --all -n argocd --wait=false 2>/dev/null || true
fi
if kubectl get crd appprojects.argoproj.io >/dev/null 2>&1; then
  strip_finalizers "appprojects.argoproj.io" "argocd"
  kubectl delete appprojects.argoproj.io --all -n argocd --wait=false 2>/dev/null || true
fi

echo "--> [2/9] Removing Ingresses and LoadBalancer Services..."
kubectl delete ingress --all --all-namespaces --timeout=30s 2>/dev/null || true

for svc in $(kubectl get svc -A --field-selector spec.type=LoadBalancer -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{end}' 2>/dev/null); do
  ns="${svc%%/*}"
  name="${svc##*/}"
  echo "Releasing LoadBalancer Service ${name} in namespace ${ns}..."
  kubectl patch svc "${name}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  kubectl delete svc "${name}" -n "${ns}" --timeout=30s 2>/dev/null || true
done

echo "Waiting 20 seconds for AWS Network Load Balancers to release..."
sleep 20

echo "--> [3/9] Removing Validating & Mutating Webhooks FIRST (Prevents Webhook Deadlocks)..."
# Delete ALL non-AWS webhooks so Kyverno/Cert-Manager/OTel don't block pod/CRD deletions
kubectl get validatingwebhookconfigurations -o name 2>/dev/null | grep -vE 'aws|eks|vpc' | xargs -r kubectl delete --timeout=10s 2>/dev/null || true
kubectl get mutatingwebhookconfigurations -o name 2>/dev/null | grep -vE 'aws|eks|vpc' | xargs -r kubectl delete --timeout=10s 2>/dev/null || true

echo "--> [4/9] Removing OpenTelemetry, Cert-Manager, and ACME Custom Resources..."
for crd in opentelemetrycollectors.opentelemetry.io instrumentations.opentelemetry.io challenges.acme.cert-manager.io certificates.cert-manager.io clusterissuers.cert-manager.io; do
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    strip_finalizers "${crd}" ""
    kubectl delete "${crd}" --all --all-namespaces --wait=false 2>/dev/null || true
  fi
done

echo "--> [5/9] Uninstalling Helm Releases..."
helm list -A --no-headers 2>/dev/null | awk '{print $1 " -n " $2}' | while read -r release; do
  if [ -n "$release" ]; then
    helm uninstall $release --no-hooks --wait=false 2>/dev/null || true
  fi
done

echo "--> [6/9] Force-Purging All Controllers, Pods & PVCs..."
for ns in "${TARGET_NAMESPACES[@]}"; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    echo "Force-cleaning workloads in namespace: ${ns}..."
    # 1. Delete controllers immediately without waiting so they stop spawning pods
    kubectl delete deployments,statefulsets,daemonsets,replicasets,jobs,cronjobs --all -n "${ns}" --wait=false 2>/dev/null || true
    
    # 2. Strip finalizers from PVCs and delete them without blocking
    strip_finalizers "pvc" "${ns}"
    kubectl delete pvc --all -n "${ns}" --wait=false 2>/dev/null || true

    # 3. Strip finalizers on any pods and force-kill all pods immediately
    strip_finalizers "pods" "${ns}"
    kubectl delete pods --all -n "${ns}" --force --grace-period=0 2>/dev/null || true
  fi
done

echo "--> [7/9] Purging Application Namespaces..."
for ns in "${TARGET_NAMESPACES[@]}"; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    # Catch any straggler pods before finalizing the namespace
    kubectl delete pods --all -n "${ns}" --force --grace-period=0 2>/dev/null || true
    kubectl delete ns "${ns}" --timeout=15s 2>/dev/null || true
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      kubectl get ns "${ns}" -o json 2>/dev/null | tr -d "\n" | sed "s/\"finalizers\": \[[^]]*\]/\"finalizers\": []/" | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true
    fi
  fi
done

echo "--> [8/9] Removing CRDs and StorageClass..."
kubectl delete storageclass gp3 2>/dev/null || true

kubectl get crd -o name 2>/dev/null | grep -E "opentelemetry.io|kyverno.io|aquasecurity.github.io|coreos.com|cert-manager.io|argoproj.io|externaldns.k8s.io|grafana.com" | while read -r crd; do
  kubectl patch "${crd}" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl delete "${crd}" --wait=false 2>/dev/null || true
done

echo "--> [9/9] Teardown complete. Remaining Pods & Namespaces:"
kubectl get pods -A
kubectl get ns