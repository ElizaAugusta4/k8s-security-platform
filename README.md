# k8s-security-platform

Plataforma Kubernetes focada em segurança, construída no GKE (Google Cloud).
Demonstra boas práticas de SRE em ambiente de produção real.

---

## Arquitetura

```
                          Internet
                              │
                    ┌─────────▼──────────┐
                    │    Cloudflare DNS   │
                    │  elizaaugusta.uk    │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │      Traefik       │
                    │  Ingress + TLS     │
                    │  35.238.161.40     │
                    └──┬──┬──┬──┬───────┘
                       │  │  │  │
           ┌───────────┘  │  │  └────────────┐
           │              │  │               │
    ┌──────▼──────┐ ┌─────▼──▼────┐ ┌───────▼──────┐
    │   Grafana   │ │    ArgoCD   │ │  secure-api  │
    │  dashboards │ │   GitOps    │ │  FastAPI+JWT │
    └─────────────┘ └─────────────┘ └──────┬───────┘
                                           │ lê segredos
┌──────────────────────────────────────────┼───────────────────────────┐
│                    GKE Cluster (privado)  │                           │
│                                          │                           │
│  ┌──────────────────┐    ┌───────────────▼────────────────────────┐  │
│  │   cert-manager   │    │              Vault                     │  │
│  │                  │    │  Modo produção + Auto Unseal via KMS   │  │
│  │  Let's Encrypt   │    │  Vault Agent Injector                  │  │
│  │  Cloudflare DNS  │    └───────────────┬────────────────────────┘  │
│  └──────────────────┘                    │                           │
│                                          │ unseal automático         │
│  ┌──────────────────┐    ┌───────────────▼────────────────────────┐  │
│  │   Prometheus     │    │           Cloud KMS                    │  │
│  │   Grafana        │    │  KeyRing: vault-keyring                │  │
│  │   AlertManager   │    │  CryptoKey: vault-unseal-key           │  │
│  └──────────────────┘    └────────────────────────────────────────┘  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                    Infraestrutura (Terraform)                   │  │
│  │  VPC privada │ Cloud NAT │ Workload Identity │ Dataplane V2    │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Stack

| Tecnologia | Versão | Função |
|---|---|---|
| GKE | 1.35.x | Cluster Kubernetes regional privado |
| Terraform | >= 1.11.0 | Provisionamento de infraestrutura |
| ArgoCD | 8.3.1 | GitOps — App-of-Apps |
| Traefik | 41.0.2 | Ingress controller + TLS termination |
| cert-manager | v1.16.3 | Certificados Let's Encrypt via Cloudflare |
| Vault | 0.29.1 | Gestão de segredos com Auto Unseal via KMS |
| kube-prometheus-stack | 87.15.1 | Observabilidade completa |
| secure-api | v1.0.2 | API FastAPI com JWT + Vault Agent Injector |

---

## Conceitos demonstrados

**Segurança em profundidade**
- Cluster privado — nodes sem IP público, API server com acesso restrito
- TLS em todos os endpoints com renovação automática via cert-manager
- Segredos gerenciados pelo Vault — zero secrets no Git ou em Secrets do Kubernetes
- Vault Agent Injector — aplicação lê segredos de arquivo, não sabe que o Vault existe
- Auto Unseal via Cloud KMS — sem intervenção manual em restarts
- Workload Identity — pods se autenticam no GCP sem chave JSON
- Security Context — containers rodam sem root com privilégios mínimos

**GitOps com ArgoCD**
- App-of-Apps — um único `kubectl apply` instala todo o stack
- Sync waves — ordem de deploy garantida por anotações
- Self-healing — qualquer mudança manual no cluster é revertida automaticamente

**Observabilidade**
- Prometheus coletando métricas de todos os componentes via ServiceMonitor
- Grafana com dashboards de cluster, nodes e aplicação
- Métricas da secure-api expostas automaticamente via prometheus-fastapi-instrumentator

**Infraestrutura como Código**
- VPC, GKE, KMS e Artifact Registry provisionados via Terraform
- State remoto no GCS com versionamento
- Módulos reutilizáveis por ambiente

---

## Endpoints da secure-api

```
POST https://api.elizaaugusta.uk/auth/register   ← registra usuário
POST https://api.elizaaugusta.uk/auth/login      ← retorna JWT token
GET  https://api.elizaaugusta.uk/users/me        ← dados do usuário (requer token)
GET  https://api.elizaaugusta.uk/health          ← health check
GET  https://api.elizaaugusta.uk/metrics         ← métricas Prometheus
GET  https://api.elizaaugusta.uk/docs            ← Swagger UI
```

---

## Estrutura do repositório

```
k8s-security-platform/
├── terraform/          ← infraestrutura (VPC, GKE, KMS, Artifact Registry)
├── argocd/             ← Applications do ArgoCD (App-of-Apps)
├── monitoring/         ← cert-manager, IngressRoutes, PrometheusRules
├── vault-config/       ← configuração do Vault via Terraform
├── helm/app-chart/     ← Helm chart reutilizável com Vault Agent Injector
├── app/                ← código da secure-api (FastAPI)
└── docs/runbook.md     ← guia operacional completo
```

---

## Como executar

Consulte o [Runbook](docs/Runbook.md) para instruções completas de provisionamento e operação.

---

## Autor

Eliza Augusta — DevOps/SRE Jr
[GitHub](https://github.com/ElizaAugusta4)
