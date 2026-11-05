##
aws eks update-kubeconfig --region ap-southeast-1 --name group2-capstone-cluster

##Deploy Ingress-NGINX::
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values common-infra/ingress-nginx/ingress-nginx-values.yaml \
  --wait
##kubectl get svc -n ingress-nginx ingress-nginx-controller

##Deploy external-dns:
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values common-infra/external-dns/external-dns-values.yaml
##kubectl logs -n external-dns deploy/external-dns --tail=30

##Deploycert-manager & ClusterIssuer:
  helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --values common-infra/cert-manager/cert-manager-values.yaml \
  --wait

kubectl apply -f common-infra/cert-manager/cluster-issuer.yaml
##kubectl get clusterissuer letsencrypt-prod

##Deploy Prometheus:
kubectl apply -f sre/prometheus/kube-prometheus-gp3.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values sre/prometheus/kube-prometheus-stack-values.yaml \
  --timeout 15m
# kubectl get pods -n monitoring
# kubectl get pvc -n monitoring

##Re-enable Ingress-NGINX ServiceMonitor
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --reuse-values \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true

kubectl apply -f prometheus/prometheus-ingress.yaml
kubectl apply -f prometheus/grafana-ingress.yaml

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --reuse-values \
  --set prometheus.enabled=true \
  --set prometheus.servicemonitor.enabled=true

helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --reuse-values \
  --set serviceMonitor.enabled=true \
  --set prometheus.servicemonitor.enabled=true