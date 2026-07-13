variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "keyring_name" {
  type    = string
  default = "vault-keyring"
}