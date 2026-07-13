# Cria uma VPC dedicada para o cluster GKE
# Nodes e pods ficam em subnets privadas — sem IP público

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false  # criamos as subnets manualmente
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr      # range dos nodes
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  # Secondary ranges para pods e services do GKE
  # GKE usa alias IPs — cada node reserva um bloco para seus pods
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Habilita Private Google Access
  # Permite que nodes sem IP público acessem APIs do GCP (GCS, Artifact Registry...)
  private_ip_google_access = true
}

# Cloud Router — necessário para o NAT funcionar
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id
}

# Cloud NAT — permite que nodes privados acessem a internet
# (para baixar imagens do Docker Hub, por exemplo)
resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}