variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região do GCP"
  type        = string
}

variable "network_name" {
  description = "Nome da VPC"
  type        = string
}

variable "subnet_name" {
  description = "Nome da subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR da subnet dos nodes"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR secundário para pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR secundário para services"
  type        = string
  default     = "10.2.0.0/20"
}