# k8s-security-platform — Runbook

Guia operacional completo do ambiente. Cobre provisionamento,
operação diária, troubleshooting e procedimentos de emergência.

---

## Visão geral

Plataforma Kubernetes focada em segurança, rodando no GKE (Google Cloud).
Demonstra boas práticas de SRE: GitOps, TLS automático, gestão de segredos,
observabilidade e controle de acesso.

### Stack

| Tecnologia | Versão | Função |
|---|---|---|
| GKE | 1.35.x | Cluster Kubernetes gerenciado |
| Traefik | 41.0.2 | Ingress controller + TLS termination |
| ArgoCD | 8.3.1 | GitOps — gerencia todos os deployments |
| cert-manager | v1.16.3 | Certificados TLS automáticos (Let's Encrypt) |
| kube-prometheus-stack | 87.15.1 | Prometheus + Grafana + AlertManager |
| Vault | 0.29.1 | Gestão de segredos |

### Domínios

| Subdomínio | Serviço |
|---|---|
| `grafana.elizaaugusta.uk` | Grafana — dashboards e alertas |
| `argocd.elizaaugusta.uk` | ArgoCD — interface GitOps |
| `vault.elizaaugusta.uk` | Vault — gestão de segredos |
| `api.elizaaugusta.uk` | secure-api — aplicação de demonstração |

### Repositório

```
https://github.com/ElizaAugusta4/k8s-security-platform
```

---

## Estrutura do projeto

```
k8s-security-platform/
├── terraform/
│   ├── modules/
│   │   ├── gke/               ← módulo do cluster GKE
│   │   └── vpc/               ← módulo de rede privada
│   └── environments/
│       └── production/        ← ambiente de produção
│           ├── backend.tf     ← state no GCS
│           ├── main.tf        ← chama os módulos vpc e gke
│           ├── variables.tf
│           └── versions.tf
├── argocd/
│   ├── root-app.yaml          ← App-of-Apps (ponto de entrada do GitOps)
│   └── apps/                  ← uma Application por serviço
│       ├── cert-manager.yaml
│       ├── cert-manager-issuers.yaml
│       ├── traefik.yaml
│       ├── kube-prometheus-stack.yaml
│       ├── ingress-routes.yaml
│       └── vault.yaml
├── monitoring/
│   ├── cert-manager/          ← ClusterIssuer e Certificates
│   ├── ingress/               ← IngressRoutes do Traefik
│   ├── rules/                 ← PrometheusRules
│   └── dashboards/            ← dashboards Grafana
├── vault-config/              ← Terraform para configurar o Vault
├── helm/
│   └── app-chart/             ← Helm chart reutilizável
├── app/
│   └── src/                   ← código da secure-api
└── docs/
    ├── runbook.md             ← este arquivo
    ├── architecture.md
    └── security.md
```

---

## Pré-requisitos

```
gcloud CLI    autenticado com conta GCP
terraform     >= 1.11.0
kubectl
helm
git
```

---

## Provisionamento inicial (primeira vez)

### 1. Criar o projeto GCP

```bash
gcloud projects create k8s-security-platformm --name="k8s Security Platform"
gcloud config set project k8s-security-platformm
gcloud billing projects link k8s-security-platformm \
  --billing-account=SEU_BILLING_ACCOUNT_ID
```

### 2. Habilitar APIs necessárias

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com
```

### 3. Criar bucket para o state do Terraform

```bash
gcloud storage buckets create gs://k8s-security-platform-tfstate \
  --project=k8s-security-platformm \
  --location=us-east1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://k8s-security-platform-tfstate \
  --versioning
```

### 4. Provisionar VPC e cluster GKE via Terraform

```bash
cd terraform/environments/production

# Cria o arquivo de variáveis (não commitado)
cat > terraform.tfvars <<EOF
project_id = "k8s-security-platformm"
region     = "us-central1"

authorized_networks = [
  {
    cidr_block   = "SEU_IP/32"
    display_name = "minha-maquina"
  }
]
EOF

terraform init
terraform plan
terraform apply
```

Tempo estimado: 10-15 minutos.

### 5. Configurar kubectl

```bash
gcloud container clusters get-credentials k8s-security-platform \
  --region us-central1 \
  --project k8s-security-platformm

kubectl get nodes
```

### 6. Instalar o ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 8.3.1 \
  --set configs.params."server\.insecure"=true \
  --set server.service.type=LoadBalancer

kubectl get pods -n argocd -w
```

### 7. Obter senha inicial do ArgoCD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 8. Criar Secret do Cloudflare para o cert-manager

```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=SEU_TOKEN_CLOUDFLARE
```

> O token é criado em: Cloudflare → My Profile → API Tokens → Edit zone DNS

### 9. Aplicar o root-app (instala tudo via GitOps)

```bash
kubectl apply -f argocd/root-app.yaml
```

Aguarda todas as Applications ficarem `Synced` e `Healthy`:

```bash
kubectl get applications -n argocd -w
```

---

## Operação diária

### Acessar os serviços

| Serviço | URL |
|---|---|
| Grafana | https://grafana.elizaaugusta.uk |
| ArgoCD | https://argocd.elizaaugusta.uk |
| Vault | https://vault.elizaaugusta.uk |
| secure-api | https://api.elizaaugusta.uk |

### Credenciais

| Serviço | Usuário | Senha |
|---|---|---|
| Grafana | admin | definida nos values do chart |
| ArgoCD | admin | obtida via secret (ver seção 7) |
| Vault | — | token root (dev) ou unseal key (prod) |

> Nunca commite credenciais. Use o Vault ou Secrets do Kubernetes.

### Ligar o cluster (após desligar para economizar)

```bash
gcloud container clusters resize k8s-security-platform \
  --num-nodes=1 \
  --region=us-central1 \
  --project=k8s-security-platformm

gcloud container clusters get-credentials k8s-security-platform \
  --region us-central1 \
  --project k8s-security-platformm
```

### Desligar o cluster (para economizar créditos)

```bash
gcloud container clusters resize k8s-security-platform \
  --num-nodes=0 \
  --region=us-central1 \
  --project=k8s-security-platformm
```

> O control plane continua rodando com custo mínimo.
> Os dados persistidos em PVCs são preservados.

### Deploy de uma mudança

```bash
# 1. Cria branch
git checkout -b feat/minha-mudanca

# 2. Faz as mudanças

# 3. Commita
git add .
git commit -m "feat: descrição da mudança"
git push -u origin feat/minha-mudanca

# 4. Abre PR no GitHub → revisa → merge
# ArgoCD detecta em até 3 minutos e aplica automaticamente
```

### Forçar sincronização imediata no ArgoCD

```bash
kubectl annotate application NOME-DA-APP -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Rollback via ArgoCD

Na UI do ArgoCD: **History and Rollback** → seleciona a versão anterior → **Rollback**.

Ou via kubectl:

```bash
kubectl rollout undo deployment/NOME -n NAMESPACE
```

---

## Terraform

### Atualizar infra

```bash
cd terraform/environments/production
terraform plan    # revisa o que vai mudar
terraform apply   # aplica
```

### Ver o que está no state

```bash
terraform state list
terraform state show module.gke.google_container_cluster.gke
```

### Reconfigurar Vault após restart (modo dev)

O Vault em modo dev perde dados ao reiniciar. Reconfigure com Terraform:

```bash
cd vault-config
kubectl port-forward -n vault svc/vault 8200:8200 &
terraform apply
```

---

## Certificados TLS

### Ver status dos certificados

```bash
kubectl get certificates -A
```

### Verificar emissão de um certificado

```bash
kubectl describe certificate grafana-tls -n monitoring
```

### Certificado não emitindo

```bash
# Ver CertificateRequests
kubectl get certificaterequest -n NAMESPACE

# Ver eventos
kubectl describe certificaterequest -n NAMESPACE NOME

# Ver logs do cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

---

## Monitoramento

### Ver alertas ativos

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# http://localhost:9093
```

### PromQL úteis

```promql
# Pods não Running
kube_pod_status_phase{phase!~"Running|Succeeded"} == 1

# Nodes com pressão de memória
kube_node_status_condition{condition="MemoryPressure",status="true"} == 1

# Certificados expirando em menos de 7 dias
(certmanager_certificate_expiration_timestamp_seconds - time()) < 7 * 24 * 3600
```

### LogQL úteis (Grafana Explore → Loki)

```logql
# Erros em todos os namespaces
{namespace=~"apps|monitoring|traefik|argocd|vault"} |= "error"

# Logs do Traefik com status 5xx
{namespace="traefik"} | json | status >= 500
```

---

## Troubleshooting

### Pod em CrashLoopBackOff

```bash
kubectl logs -n NAMESPACE POD --previous
kubectl describe pod -n NAMESPACE POD
```

### ArgoCD OutOfSync

```bash
kubectl describe application NOME -n argocd | grep -A5 Message
```

### Traefik não roteando

```bash
kubectl get ingressroute -A
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50
```

### Certificado não sendo emitido

```bash
kubectl describe certificaterequest -n NAMESPACE
kubectl logs -n cert-manager -l app=cert-manager | grep error
```

### Node NotReady

```bash
kubectl describe node NOME-DO-NODE
kubectl get events -n kube-system --sort-by='.lastTimestamp'
```

---

## Procedimentos de emergência

### Cluster inacessível

```bash
# Verifica se o cluster existe
gcloud container clusters list --project=k8s-security-platformm

# Reconfigura kubectl
gcloud container clusters get-credentials k8s-security-platform \
  --region us-central1 --project k8s-security-platformm
```

### Rollback do Terraform

```bash
cd terraform/environments/production
terraform state list                    # lista recursos
terraform plan -destroy -target=RECURSO # preview do destroy
terraform apply -target=RECURSO         # aplica só esse recurso
```

### Destruir tudo (cuidado)

```bash
cd terraform/environments/production
terraform destroy
```

---

## Custos estimados

| Recurso | Custo estimado/dia |
|---|---|
| 3x e2-standard-2 Spot | R$ 8-12 |
| Control plane GKE | R$ 2 |
| Load Balancers (3x) | R$ 3 |
| **Total com cluster ligado** | **~R$ 15/dia** |
| **Total com nodes desligados** | **~R$ 2/dia** |

> Desligue os nodes quando não estiver usando para economizar créditos.
