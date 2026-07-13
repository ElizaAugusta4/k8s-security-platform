resource "vault_policy" "secure_api" {
  name = "secure-api"

  policy = <<EOT
path "secret/data/secure-api/*" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOT
}