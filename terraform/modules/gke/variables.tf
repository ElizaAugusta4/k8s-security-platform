variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "cluster_name" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "master_cidr" {
  description = "CIDR do control plane gerenciado pelo GCP (não pode sobrepor outros ranges)"
  type        = string
  default     = "172.16.0.0/28"   # range pequeno, só para o control plane
}

variable "authorized_networks" {
  description = "IPs que podem acessar o API server"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "node_count" {
  description = "Nodes por zona"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Tipo de máquina dos nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "use_spot_nodes" {
  description = "Usar Spot VMs (mais barato, pode ser interrompido)"
  type        = bool
  default     = true
}

variable "environment" {
  type    = string
  default = "production"
}