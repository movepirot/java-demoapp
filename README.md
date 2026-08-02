# AKS Demo — Terraform + GitOps + Observability

## Architecture

```
GitHub Actions  →  ACR (container image)
                →  Git commit (image tag bump)
                           ↓
                        ArgoCD  →  AKS (deploy)
                                     ↓
                              Prometheus / Grafana / Loki
```

## Prerequisites

- Azure CLI (`az`) authenticated
- Terraform >= 1.5
- kubectl, helm, kustomize

## Quick Start

### 1 — Provision infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### 2 — Bootstrap the cluster

```bash
# Edit k8s/argocd/app-java.yaml and app-monitoring.yaml — set your repoURL
bash scripts/bootstrap.sh
```

### 3 — Set GitHub Actions secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CREDENTIALS` | JSON output of `az ad sp create-for-rbac --sdk-auth` |
| `ACR_LOGIN_SERVER` | e.g. `aksdemoregistry.azurecr.io` |
| `ACR_USERNAME` | ACR admin username |
| `ACR_PASSWORD` | ACR admin password |
| `ACR_NAME` | ACR resource name (for Terraform) |

Get ACR credentials after `terraform apply`:
```bash
terraform output -raw acr_admin_username
terraform output -raw acr_admin_password
```

## Components

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| demo-app | demo-app | Spring Boot REST API |
| ArgoCD | argocd | GitOps controller |
| kube-prometheus-stack | monitoring | Prometheus + Grafana + Alertmanager |
| Loki | monitoring | Log aggregation |
| Promtail | monitoring | Log shipper (DaemonSet) |

## Accessing services

```bash
# Grafana (admin / admin)
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# ArgoCD UI
kubectl get svc -n argocd argocd-server

# Java app
kubectl get svc -n demo-app demo-app
```

## CI/CD Flow

1. Push to `main` under `java-app/` triggers **build.yml**
2. Maven build + tests run
3. Docker image pushed to ACR tagged with Git SHA
4. `kustomization.yaml` image tag updated and committed
5. ArgoCD detects the manifest change and syncs the deployment

## Terraform Backend

The state backend is Azure Blob Storage. Create it once before first `terraform init`:

```bash
az group create -n tfstate-rg -l eastus
az storage account create -n tfstatestore -g tfstate-rg --sku Standard_LRS
az storage container create -n tfstate --account-name tfstatestore
```

## Cost Notes

- AKS management plane: **free** (`sku_tier = "Free"`)
- 2 × Standard_B2s nodes: ~$60/month
- ACR Basic: ~$5/month
- Reduce cost: set `node_count = 1` in `terraform/variables.tf` for dev
