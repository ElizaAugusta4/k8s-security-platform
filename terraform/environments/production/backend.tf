# Onde o state do Terraform fica guardado
# GCS com versionamento — permite recuperar versões anteriores
terraform {
  backend "gcs" {
    bucket = "k8s-security-platform-tfstate"
    prefix = "production"
  }
}