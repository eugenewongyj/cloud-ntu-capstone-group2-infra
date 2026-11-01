# Platform Add-ons Deployment Guide (Helm CLI)

This guide documents the step-by-step deployment of core platform add-ons on Amazon EKS Auto Mode using Helm CLI and declarative `values.yaml` files.

---

## Architecture Overview

```text
User Request (https://*.sctp-sandbox.com)
       │
       ▼
[ Route 53 Hosted Zone ]  ◄────── (Syncs A/TXT records) ────── [ ExternalDNS ]
       │                                                             ▲
       ▼                                                             │ Watches Ingress
[ AWS NLB / Ingress-NGINX ] ──────────────────────────────────────────┼───────────────┐
       │                                                             │               │
       ├─────────────────────────────────┐                           │               │
       ▼                                 ▼                           │               │
[ Grafana Service ]            [ Let's Encrypt HTTP-01 ] ◄──── [ cert-manager ]     │
  (monitoring namespace)         (ACME solver challenge)       (Issues TLS Secret)   │
       │                                                                             │
[ Persistent Storage ]                                                               │
  (EBS CSI - gp3 / emptyDir)                                                        │
       ▲                                                                             │
       └─────────────────────────────────────────────────────────────────────────────┘


1. aws eks update-kubeconfig --region ap-southeast-1 --name group2-tk-cluster

2. register helm repo
helm repo add ingress-nginx [https://kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx)
helm repo add external-dns [https://kubernetes-sigs.github.io/external-dns/](https://kubernetes-sigs.github.io/external-dns/)
helm repo add jetstack [https://charts.jetstack.io](https://charts.jetstack.io)
helm repo add prometheus-community [https://prometheus-community.github.io/helm-charts](https://prometheus-community.github.io/helm-charts)
helm repo update

3. deployment and verification
ingress:
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values helm/ingress-nginx-values.yaml \
  --wait

kubectl get svc -n ingress-nginx ingress-nginx-controller

external-dns:
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values helm/external-dns-values.yaml

  kubectl logs -n external-dns deploy/external-dns --tail=30

  cert-manager & ClusterIssuer:
  helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --values helm/cert-manager-values.yaml \
  --wait

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@sctp-sandbox.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl get clusterissuer letsencrypt-prod

Prometheus:
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values helm/kube-prometheus-stack-values.yaml \
  --timeout 15m

kubectl get pods -n monitoring
kubectl get pvc -n monitoring

kubectl apply -f helm/prometheus-ingress.yaml

# 1. Verify ExternalDNS registers the record
kubectl logs -n external-dns deploy/external-dns --tail=15

# 2. Check TLS certificate issuance
kubectl get certificate -n monitoring group2-tk-prometheus-tls -w

# 3. Test HTTPS endpoint
curl -Iv [https://group2-tk-prometheus.sctp-sandbox.com](https://group2-tk-prometheus.sctp-sandbox.com)