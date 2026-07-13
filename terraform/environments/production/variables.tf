variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região principal"
  type        = string
  default     = "us-east1"
}

variable "authorized_networks" {
  description = "IPs autorizados a acessar o API server do GKE"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}