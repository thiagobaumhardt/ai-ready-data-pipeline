output "airflow_webserver_url" {
  description = "URL da UI do Airflow"
  value       = "http://localhost:${var.airflow_webserver_host_port}"
}

output "admin_username" {
  description = "Usuário admin do Airflow"
  value       = var.admin_username
}

output "admin_password" {
  description = "Senha do usuário admin do Airflow"
  value       = var.admin_password
  sensitive   = true
}

output "cluster_name" {
  description = "Nome do cluster kind criado"
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado para o cluster kind"
  value       = kind_cluster.this.kubeconfig_path
}
