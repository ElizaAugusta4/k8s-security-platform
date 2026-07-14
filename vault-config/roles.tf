resource "vault_kubernetes_auth_backend_role" "secure_api" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "secure-api"
  bound_service_account_names      = ["secure-api"]
  bound_service_account_namespaces = ["apps"]
  token_policies                   = [vault_policy.secure_api.name]
  token_ttl                        = 3600
  token_max_ttl                    = 86400
  alias_name_source                = "serviceaccount_name" 
}