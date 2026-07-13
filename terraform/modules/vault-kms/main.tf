# terraform/modules/vault-kms/main.tf
#
# Cria os recursos do Cloud KMS para Auto Unseal do Vault
# O Vault usa essa chave para criptografar/decriptografar sua master key

resource "google_kms_key_ring" "vault" {
  name     = var.keyring_name
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "vault_unseal" {
  name            = "vault-unseal-key"
  key_ring        = google_kms_key_ring.vault.id
  rotation_period = "7776000s"  # rotação a cada 90 dias

  lifecycle {
    prevent_destroy = true  # nunca destruir — perderia acesso aos dados do Vault
  }
}

# Service Account do GCP para o Vault
resource "google_service_account" "vault" {
  account_id   = "vault-sa"
  display_name = "Vault Service Account"
  project      = var.project_id
}

# Permissão para o SA usar a chave KMS
resource "google_kms_crypto_key_iam_member" "vault_unseal" {
  crypto_key_id = google_kms_crypto_key.vault_unseal.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vault.email}"
}

# Workload Identity — liga o SA do Kubernetes ao SA do GCP
# O pod do Vault usa o SA do K8s e o GCP reconhece como o SA do GCP
resource "google_service_account_iam_member" "vault_workload_identity" {
  service_account_id = google_service_account.vault.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[vault/vault]"
}