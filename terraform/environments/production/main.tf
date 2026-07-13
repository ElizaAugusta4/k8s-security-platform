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

# Outputs para uso posterior (ArgoCD, kubectl, etc.)
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