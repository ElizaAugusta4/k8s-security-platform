# terraform/modules/gke/main.tf
#
# Cria um cluster GKE privado com boas práticas de segurança:
# - Nodes sem IP público
# - API server com acesso restrito
# - Workload Identity habilitado
# - Dataplane V2 (Cilium/eBPF) para Network Policy

resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Remove o node pool padrão — vamos criar um separado
  # com configurações específicas
  remove_default_node_pool = true
  initial_node_count       = 1

  # Rede onde o cluster vai rodar
  network    = var.network_name
  subnetwork = var.subnet_name

  # VPC-native — usa alias IPs (obrigatório para cluster privado)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Cluster privado — nodes e API server sem IP público
  private_cluster_config {
    enable_private_nodes    = true   # nodes sem IP público
    enable_private_endpoint = false  # API server ainda acessível externamente
                                     # mas só pelos IPs autorizados abaixo
    master_ipv4_cidr_block  = var.master_cidr  # range do control plane gerenciado
  }

  # IPs que podem acessar o API server
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity — pods se autenticam no GCP sem chave JSON
  # Equivalente ao que vimos no loki-sa e stackdriver-exporter
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Dataplane V2 — baseado em Cilium/eBPF
  # Habilita Network Policy nativa e observabilidade de rede
  datapath_provider = "ADVANCED_DATAPATH"

  # Release channel — define como o cluster recebe atualizações
  # REGULAR: versões testadas, atualizações automáticas mensais
  release_channel {
    channel = "REGULAR"
  }

  # Proteção contra delete acidental
  deletion_protection = false  # true em produção real
  # Configuração do node pool temporário (removido após criação)
  # Necessário para evitar que o GKE use SSD por padrão

  # Logging e monitoring nativos do GCP
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
}

# Node pool separado — permite atualizar nodes sem recriar o cluster
resource "google_container_node_pool" "nodes" {
  name     = "${var.cluster_name}-nodes"
  location = var.region
  cluster  = google_container_cluster.gke.name
  project  = var.project_id

  # Número de nodes por zona
  # Com region (não zone), o GKE cria nodes em 3 zonas automaticamente
  node_count = var.node_count

  # Atualização automática dos nodes
  management {
    auto_repair  = true   # repara nodes com problema automaticamente
    auto_upgrade = true   # atualiza nodes quando o cluster atualiza
  }

  node_config {
    machine_type = var.machine_type   # e2-standard-2 para lab
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Spot VMs — até 90% mais baratas, podem ser interrompidas
    # Ideal para lab e workloads tolerantes a interrupção
    spot = var.use_spot_nodes

    # Workload Identity no node pool
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # OAuth scopes mínimos necessários
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    # Labels nos nodes
    labels = {
      environment = var.environment
      managed_by  = "terraform"
    }

    # Shielded nodes — proteção contra rootkits no boot
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Atualiza nodes com rolling update
  upgrade_settings {
    max_surge       = 1  # cria 1 node novo antes de remover 1 antigo
    max_unavailable = 0  # nunca deixa nodes indisponíveis durante update
  }
}