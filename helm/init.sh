##Update kubeconfig for EKS cluster
aws eks update-kubeconfig --region ap-southeast-1 --name group2-capstone-cluster

##Deploy Ingress-NGINX::
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values ingress-nginx/ingress-nginx-values.yaml \
  --wait
##kubectl get svc -n ingress-nginx ingress-nginx-controller

##Deploy external-dns:
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values external-dns/external-dns-values.yaml
##kubectl logs -n external-dns deploy/external-dns --tail=30

##Deploycert-manager & ClusterIssuer:
  helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --values cert-manager/cert-manager-values.yaml \
  --wait

kubectl apply -f cert-manager/cluster-issuer.yaml
##kubectl get clusterissuer letsencrypt-prod

##Deploy Prometheus:
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values prometheus/kube-prometheus-stack-values.yaml \
  --timeout 15m
# kubectl get pods -n monitoring
# kubectl get pvc -n monitoring

##Re-enable Ingress-NGINX ServiceMonitor
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --reuse-values \
  --set controller.metrics.serviceMonitor.enabled=true

kubectl apply -f prometheus/prometheus-ingress.yaml
kubectl apply -f prometheus/grafana-ingress.yaml
