# Módulo VPC — cria a rede privada
module "vpc" {
  source = "../../modules/vpc"
  project_id   = var.project_id
  region       = var.region
  network_name = "k8s-security-platform-vpc"
  subnet_name  = "k8s-security-platform-subnet"
  subnet_cidr  = "10.0.0.0/24"
  pods_cidr    = "10.1.0.0/16"
  services_cidr = "10.2.0.0/20"
}

# Módulo GKE — cria o cluster privado
module "gke" {
  source = "../../modules/gke"
  project_id   = var.project_id
  region       = var.region
  cluster_name = "k8s-security-platform"
  network_name = module.vpc.network_name
  subnet_name  = module.vpc.subnet_name
  master_cidr         = "172.16.0.0/28"
  authorized_networks = var.authorized_networks
  node_count     = 1
  machine_type   = "e2-standard-2"
  use_spot_nodes = true
  environment    = "production"
  depends_on = [module.vpc]
}

output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "configure_kubectl" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

# Módulo KMS — para Auto Unseal do Vault
module "vault_kms" {
  source = "../../modules/vault-kms"
  project_id   = var.project_id
  region       = var.region
  keyring_name = "vault-keyring"
  depends_on = [module.gke]
}

output "vault_crypto_key_id" {
  value = module.vault_kms.crypto_key_id
}

output "vault_sa_email" {
  value = module.vault_kms.vault_sa_email
}

# Artifact Registry — armazena as imagens Docker do projeto
resource "google_artifact_registry_repository" "secure_api" {
  project       = var.project_id
  location      = var.region
  repository_id = "secure-api"
  format        = "DOCKER"
  description   = "Imagens Docker da secure-api"
}

data "google_project" "project" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository_iam_member" "gke_pull" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.secure_api.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

output "registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/secure-api"
}