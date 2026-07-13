# k8s-security-platform

# Cria o projeto
gcloud projects create k8s-security-platformm --name="k8s Security Platform2"

# Define como projeto ativo
gcloud config set project k8s-security-platformm

# Confirma
gcloud config list project

# Lista os billing accounts disponíveis
gcloud billing accounts list

# Vincula o billing ao project
gcloud billing projects link k8s-security-platformm `
  --billing-account=xxxxxx-xxxxxx-xxxxxx

# Habilitar Apis necessárias para o projeto 
gcloud services enable `
  container.googleapis.com `
  compute.googleapis.com `
  cloudresourcemanager.googleapis.com `
  iam.googleapis.com `
  secretmanager.googleapis.com

# Estrutura de Pastas e sua representação 

k8s-security-platform/
│
├── terraform/                 ← provisiona a infra no GCP
│   ├── modules/               ← módulos reutilizáveis (igual ao ids-root-module-iac)
│   │   ├── gke/               ← cria o cluster GKE
│   │   └── vpc/               ← cria a rede privada
│   └── environments/
│       └── production/        ← configuração específica do ambiente
│
├── helm/
│   └── app-chart/             ← chart reutilizável com security best practices
│       └── templates/
│
├── argocd/
│   └── apps/                  ← Applications do ArgoCD (App-of-Apps)
│
├── vault-config/              ← Terraform para configurar políticas e segredos
│
├── monitoring/
│   ├── rules/                 ← PrometheusRules de segurança
│   └── dashboards/            ← dashboards Grafana
│
├── app/
│   └── src/                   ← código da secure-api (FastAPI)
│
└── docs/
    ├── architecture.md        ← diagrama e decisões de arquitetura
    ├── runbook.md             ← como operar o ambiente
    └── security.md            ← decisões de segurança documentadas

# Ordem da Construção do Projeto 

# 1. VPC (rede privada)          ← o cluster precisa de uma rede
# 2. GKE (cluster)               ← provisiona dentro da VPC
# 3. Vault (no cluster)          ← precisa do cluster rodando
# 4. ArgoCD (no cluster)         ← gerencia tudo depois
# 5. Apps via ArgoCD             ← Traefik, Prometheus, Loki, cert-manager, secure-api


# Cria o bucket para o state do Terraform
gcloud storage buckets create gs://k8s-security-platform-tfstate `
  --project=k8s-security-platformm `
  --location=us-east1 `
  --uniform-bucket-level-access

# Habilita versionamento — permite recuperar state antigo se corromper
gcloud storage buckets update gs://k8s-security-platform-tfstate `
  --versioning


helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Cria o namespace
kubectl create namespace argocd

# Instala o ArgoCD
helm install argocd argo/argo-cd `
  --namespace argocd `
  --version 7.8.23 `
  --set configs.params."server\.insecure"=true `
  --set server.service.type=LoadBalancer

# Aguarda subir
kubectl get pods -n argocd -w


# IP externo do LoadBalancer
kubectl get svc argocd-server -n argocd

# Senha inicial
kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath="{.data.password}" | `
  ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }