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
| GKE | 1.35.x | Cluster Kubernetes gerenciado (us-central1, regional) |
| Traefik | 41.0.2 | Ingress controller + TLS termination |
| ArgoCD | 8.3.1 | GitOps — gerencia todos os deployments |
| cert-manager | v1.16.3 | Certificados TLS automáticos (Let's Encrypt + Cloudflare) |
| kube-prometheus-stack | 87.15.1 | Prometheus + Grafana + AlertManager |
| Vault | 0.29.1 | Gestão de segredos — modo produção com Auto Unseal via KMS |
| Cloud KMS | — | Auto Unseal do Vault via chave criptográfica gerenciada |
| Artifact Registry | — | Registry Docker para imagens da secure-api |
| secure-api | v1.0.2 | API FastAPI com autenticação JWT e métricas Prometheus |

### Domínios

| Subdomínio | Serviço | Certificado |
|---|---|---|
| `grafana.elizaaugusta.uk` | Grafana | Let's Encrypt (válido) |
| `argocd.elizaaugusta.uk` | ArgoCD | Let's Encrypt (válido) |
| `vault.elizaaugusta.uk` | Vault | Let's Encrypt (válido) |
| `api.elizaaugusta.uk` | secure-api | Let's Encrypt (válido) |

> DNS gerenciado pelo Cloudflare. Todos os registros A apontam para o IP do Traefik.

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
│   │   ├── gke/               ← módulo do cluster GKE privado
│   │   ├── vpc/               ← módulo de rede privada com Cloud NAT
│   │   └── vault-kms/         ← módulo KMS para Auto Unseal do Vault
│   └── environments/
│       └── production/
│           ├── backend.tf     ← state no GCS
│           ├── main.tf        ← VPC, GKE, KMS, Artifact Registry
│           ├── variables.tf
│           └── versions.tf
├── argocd/
│   ├── root-app.yaml          ← App-of-Apps (ponto de entrada do GitOps)
│   └── apps/
│       ├── cert-manager.yaml
│       ├── cert-manager-issuers.yaml
│       ├── traefik.yaml
│       ├── kube-prometheus-stack.yaml
│       ├── ingress-routes.yaml
│       ├── vault.yaml
│       └── secure-api.yaml
├── monitoring/
│   ├── cert-manager/          ← ClusterIssuer (Let's Encrypt + Cloudflare) e Certificates
│   ├── ingress/               ← IngressRoutes do Traefik
│   ├── rules/                 ← PrometheusRules
│   └── dashboards/            ← dashboards Grafana
├── vault-config/              ← Terraform para configurar o Vault
│   ├── main.tf                ← provider Vault
│   ├── auth.tf                ← Auth Method Kubernetes
│   ├── secrets.tf             ← Engine KV e segredos
│   ├── policies.tf            ← políticas de acesso
│   ├── roles.tf               ← roles Kubernetes
│   └── variables.tf
├── helm/
│   └── app-chart/             ← Helm chart reutilizável com Vault Agent Injector
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── serviceaccount.yaml
│           ├── ingressroute.yaml
│           └── servicemonitor.yaml
├── app/
│   ├── src/                   ← código da secure-api (FastAPI)
│   │   ├── main.py            ← rotas e métricas
│   │   ├── auth.py            ← JWT e autenticação
│   │   ├── database.py        ← SQLite via SQLAlchemy
│   │   ├── models.py          ← modelos Pydantic
│   │   └── vault.py           ← lê segredos injetados pelo Vault Agent
│   ├── Dockerfile
│   └── requirements.txt
└── docs/
    └── runbook.md             ← este arquivo
```

---

## Pré-requisitos

```
gcloud CLI    autenticado com conta GCP
terraform     >= 1.11.0
kubectl
helm
git
docker
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
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  artifactregistry.googleapis.com
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

### 4. Provisionar infra via Terraform

```bash
cd terraform/environments/production

# Cria o arquivo de variáveis (não commitado — está no .gitignore)
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

Tempo estimado: 10-15 minutos. O Terraform cria:
- VPC privada com subnets, Cloud Router e Cloud NAT
- Cluster GKE regional com Workload Identity e Dataplane V2
- KMS KeyRing `vault-keyring` e CryptoKey `vault-unseal-key`
- Service Account `vault-sa` com permissões KMS
- Artifact Registry `secure-api` para imagens Docker

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
# Token criado em: Cloudflare → My Profile → API Tokens → Edit zone DNS
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=SEU_TOKEN_CLOUDFLARE
```

### 9. Criar namespaces necessários

```bash
kubectl create namespace apps
kubectl create namespace vault
```

### 10. Aplicar o root-app (instala tudo via GitOps)

```bash
kubectl apply -f argocd/root-app.yaml
```

Aguarda todas as Applications ficarem `Synced` e `Healthy`:

```bash
kubectl get applications -n argocd -w
```

Ordem de sync por wave:
- Wave 0: cert-manager, Traefik, kube-prometheus-stack
- Wave 1: cert-manager-issuers, Vault, ingress-routes
- Wave 2: secure-api

### 11. Inicializar o Vault (apenas na primeira vez)

```bash
kubectl exec -n vault vault-0 -- vault operator init
```

Retorna 5 **Recovery Keys** e o **Root Token**.
- Guarde as recovery keys em local seguro offline
- O Root Token é necessário para configurar o Vault via Terraform
- Após o init, o Vault se dessela automaticamente via Cloud KMS

> NUNCA commite recovery keys ou root token no Git.

### 12. Configurar o Vault via Terraform

```bash
cd vault-config

# Em outro terminal — mantém rodando
kubectl port-forward -n vault svc/vault 8200:8200

# Aplica a configuração
export TF_VAR_vault_root_token=SEU_ROOT_TOKEN
export TF_VAR_kubernetes_host=https://IP-DO-CLUSTER
export TF_VAR_app_secret_key=CHAVE-SECRETA-DA-API
export TF_VAR_db_password=SENHA-DO-BANCO

terraform init
terraform apply
```

O Terraform configura:
- Auth Method Kubernetes com `kubernetes_host: https://kubernetes.default.svc`
- Engine KV v2 em `secret/`
- Segredos da secure-api em `secret/secure-api/config`
- Policy `secure-api` com acesso somente leitura
- Role Kubernetes ligando o SA `secure-api` no namespace `apps`

### 13. Build e push da imagem da secure-api

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev

cd app
docker build -t us-central1-docker.pkg.dev/k8s-security-platformm/secure-api/secure-api:v1.0.2 .
docker push us-central1-docker.pkg.dev/k8s-security-platformm/secure-api/secure-api:v1.0.2
```

---

## Operação diária

### Acessar os serviços

| Serviço | URL |
|---|---|
| Grafana | https://grafana.elizaaugusta.uk |
| ArgoCD | https://argocd.elizaaugusta.uk |
| Vault | https://vault.elizaaugusta.uk |
| secure-api docs | https://api.elizaaugusta.uk/docs |

### Testar a secure-api

```bash
# Registrar usuário
curl -X POST https://api.elizaaugusta.uk/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@test.com","password":"senha123","name":"User"}'

# Login
curl -X POST https://api.elizaaugusta.uk/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@test.com","password":"senha123"}'

# Endpoint protegido (substitui TOKEN pelo access_token retornado no login)
curl https://api.elizaaugusta.uk/users/me \
  -H "Authorization: Bearer TOKEN"
```

### Ligar o cluster

```bash
gcloud container clusters resize k8s-security-platform \
  --num-nodes=1 \
  --region=us-central1 \
  --project=k8s-security-platformm

gcloud container clusters get-credentials k8s-security-platform \
  --region us-central1 \
  --project k8s-security-platformm
```

> O Vault se dessela automaticamente via Cloud KMS após o pod subir.
> Não é necessário nenhum unseal manual.

### Desligar o cluster

```bash
gcloud container clusters resize k8s-security-platform \
  --num-nodes=0 \
  --region=us-central1 \
  --project=k8s-security-platformm
```

> PVCs (dados do Vault), certificados e state do Terraform são preservados.

### Deploy de uma mudança

```bash
git checkout -b feat/minha-mudanca
# faz as mudanças
git add .
git commit -m "feat: descrição da mudança"
git push -u origin feat/minha-mudanca
# abre PR → revisa → merge
# ArgoCD detecta em até 3 minutos e aplica automaticamente
```

### Nova versão da secure-api

```bash
docker build -t us-central1-docker.pkg.dev/k8s-security-platformm/secure-api/secure-api:NOVA_TAG .
docker push us-central1-docker.pkg.dev/k8s-security-platformm/secure-api/secure-api:NOVA_TAG
# atualiza image.tag no helm/app-chart/values.yaml
# commita e faz push → ArgoCD faz o rolling update automaticamente
```

### Forçar sincronização no ArgoCD

```bash
kubectl annotate application NOME -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## Terraform

### Atualizar infra

```bash
cd terraform/environments/production
terraform plan
terraform apply
```

### Ver outputs

```bash
terraform output
# registry_url, cluster_name, vault_crypto_key_id, vault_sa_email
```

### Reconfigurar Vault após perda de state

```bash
cd vault-config
kubectl port-forward -n vault svc/vault 8200:8200 &
terraform import vault_mount.kv secret
terraform import vault_auth_backend.kubernetes kubernetes
terraform apply
```

---

## Vault — operação

### Verificar status

```bash
kubectl exec -n vault vault-0 -- vault status
# Sealed: false  → dessealado automaticamente via KMS
# Seal Type: gcpckms
```

### Vault selado após restart

Em produção com Cloud KMS o Vault se dessela automaticamente.
Se aparecer `Sealed: true`, verifica os logs:

```bash
kubectl logs -n vault vault-0 --tail=30
```

Causas comuns: problema de Workload Identity ou permissão KMS.

### Adicionar novo segredo

```bash
# Via port-forward
kubectl port-forward -n vault svc/vault 8200:8200
VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=ROOT_TOKEN \
  vault kv put secret/nova-app/config chave=valor

# Via Terraform (recomendado)
# adiciona em vault-config/secrets.tf e aplica
```

---

## Certificados TLS

### Ver status

```bash
kubectl get certificates -A
# Todos devem aparecer com READY: True
```

### Certificado não emitindo

```bash
kubectl describe certificaterequest -n NAMESPACE NOME
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Verifica o token do Cloudflare
kubectl get secret cloudflare-api-token -n cert-manager -o yaml
```

---

## Monitoramento

### PromQL úteis

```promql
# Pods não Running
kube_pod_status_phase{phase!~"Running|Succeeded"} == 1

# Nodes com pressão de memória
kube_node_status_condition{condition="MemoryPressure",status="true"} == 1

# Certificados expirando em menos de 7 dias
(certmanager_certificate_expiration_timestamp_seconds - time()) < 7 * 24 * 3600

# Taxa de erro da secure-api
sum(rate(http_requests_total{status=~"5.."}[5m]))
/ sum(rate(http_requests_total[5m]))

# Latência P95 da secure-api
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{app="secure-api"}[5m]))
)
```

### LogQL úteis

```logql
# Erros em todos os namespaces
{namespace=~"apps|monitoring|traefik|argocd|vault"} |= "error"

# Logs da secure-api
{namespace="apps", app="secure-api"}

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

### Vault Agent não injetando segredos (403)

```bash
# Verifica se o role existe e está correto
kubectl exec -n vault vault-0 -- \
  sh -c "VAULT_TOKEN=ROOT_TOKEN vault read auth/kubernetes/role/secure-api"

# Verifica se o kubernetes_host está correto
kubectl exec -n vault vault-0 -- \
  sh -c "VAULT_TOKEN=ROOT_TOKEN vault read auth/kubernetes/config"
# kubernetes_host deve ser: https://kubernetes.default.svc

# Verifica logs do vault-agent-init
kubectl logs -n apps POD -c vault-agent-init --tail=20
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

### Node NotReady

```bash
kubectl describe node NOME-DO-NODE
kubectl get events -n kube-system --sort-by='.lastTimestamp'
```

---

## Procedimentos de emergência

### Cluster inacessível

```bash
gcloud container clusters list --project=k8s-security-platformm
gcloud container clusters get-credentials k8s-security-platform \
  --region us-central1 --project k8s-security-platformm
```

### Vault inacessível (KMS indisponível)

```bash
# Unseal manual de emergência com recovery keys
kubectl exec -it -n vault vault-0 -- vault operator unseal
# Insere 3 das 5 recovery keys geradas no vault operator init
```

### Destruir tudo

```bash
# Remove o Vault primeiro (evita conflito com KMS)
kubectl delete application vault -n argocd

cd terraform/environments/production
terraform destroy

# A CryptoKey do KMS tem lifecycle prevent_destroy
# Para destruir: remova o lifecycle block antes
```

---

## Custos estimados

| Recurso | Com nodes ligados | Com nodes desligados |
|---|---|---|
| 3x e2-standard-2 Spot (1/zona) | R$ 20-25/dia | R$ 0 |
| Control plane GKE regional | R$ 12/dia | R$ 12/dia |
| 3x Load Balancers | R$ 9/dia | R$ 9/dia |
| PVC Vault (5Gi) | R$ 0.10/dia | R$ 0.10/dia |
| Cloud KMS | ~R$ 0.10/dia | ~R$ 0.10/dia |
| Artifact Registry | ~R$ 0.05/dia | ~R$ 0.05/dia |
| **Total** | **~R$ 42/dia** | **~R$ 21/dia** |

> Com R$ 1.700 de créditos trial: ~40 dias ligado ou ~80 dias desligado à noite.
> Desligue os nodes quando não estiver usando para economizar créditos.
