kubectl delete ingress -n monitoring --all --ignore-not-found
kubectl delete ingress -n default --all --ignore-not-found
#kubectl delete deployment echo-test -n default --ignore-not-found
kubectl delete svc echo-test -n default --ignore-not-found

helm uninstall kube-prometheus-stack -n monitoring
helm uninstall cert-manager -n cert-manager
helm uninstall external-dns -n external-dns
helm uninstall ingress-nginx -n ingress-nginx

kubectl delete pvc -n monitoring --all

kubectl delete clusterissuer letsencrypt-prod --ignore-not-found
kubectl delete secret -n monitoring grafana-tls-cert group2-tk-grafana-tls --ignore-not-found