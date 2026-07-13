variable "vault_root_token" {
  type      = string
  sensitive = true
}

variable "kubernetes_host" {
  description = "Endpoint do API server do GKE"
  type        = string
}