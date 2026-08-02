#!/usr/bin/env bash
# Bootstraps the cluster after Terraform apply:
# 1. Gets AKS credentials
# 2. Installs ArgoCD
# 3. Installs monitoring stack (kube-prometheus-stack + Loki + Promtail)
# 4. Registers ArgoCD apps

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-aks-demo-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-demo}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"

echo "==> Getting AKS credentials"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "==> Creating namespaces"
kubectl apply -f k8s/namespaces.yaml

# ---------- ArgoCD ----------
echo "==> Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

echo "==> Waiting for ArgoCD to be ready"
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Patching ArgoCD server to LoadBalancer (dev convenience)"
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

echo "==> ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# ---------- Helm repos ----------
echo "==> Adding Helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ---------- Monitoring ----------
echo "==> Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values k8s/monitoring/kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 10m

echo "==> Installing Loki"
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values k8s/monitoring/loki-values.yaml \
  --wait \
  --timeout 5m

echo "==> Installing Promtail"
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --values k8s/monitoring/promtail-values.yaml \
  --wait \
  --timeout 5m

# ---------- ArgoCD apps ----------
echo "==> Registering ArgoCD project and applications"
kubectl apply -f k8s/argocd/project.yaml
kubectl apply -f k8s/argocd/app-java.yaml
kubectl apply -f k8s/argocd/app-monitoring.yaml

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Grafana:"
kubectl get svc -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}' 2>/dev/null && echo " (admin/admin)"
echo ""
echo "ArgoCD:"
kubectl get svc -n argocd argocd-server \
  -o jsonpath='https://{.status.loadBalancer.ingress[0].ip}' 2>/dev/null && echo " (admin/<password above>)"
