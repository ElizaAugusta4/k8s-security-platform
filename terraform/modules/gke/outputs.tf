output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.gke.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_identity_pool" {
  value = "${var.project_id}.svc.id.goog"
}
