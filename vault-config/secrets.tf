# Engine KV v2
resource "vault_mount" "kv" {
  path    = "secret"
  type    = "kv"
  options = { version = "2" }
}

# Segredos da secure-api
resource "vault_kv_secret_v2" "secure_api" {
  mount = vault_mount.kv.path
  name  = "secure-api/config"

  data_json = jsonencode({
    app_secret_key = var.app_secret_key
    db_password    = var.db_password
  })
}

variable "app_secret_key" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}