output "airflow_webserver_url" {
  description = "URL of the Airflow UI"
  value       = "http://localhost:${var.airflow_webserver_host_port}"
}

output "admin_username" {
  description = "Airflow admin user"
  value       = var.admin_username
}

output "admin_password" {
  description = "Airflow admin password"
  value       = var.admin_password
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the created kind cluster"
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig for the kind cluster"
  value       = kind_cluster.this.kubeconfig_path
}
