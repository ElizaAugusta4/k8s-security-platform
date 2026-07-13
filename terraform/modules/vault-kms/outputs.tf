output "crypto_key_id" {
  value = google_kms_crypto_key.vault_unseal.id
}

output "vault_sa_email" {
  value = google_service_account.vault.email
}

output "keyring_name" {
  value = google_kms_key_ring.vault.name
}