output "project_id" {
  description = "ID do projeto GCP autenticado"
  value       = var.project_id
}

output "region" {
  description = "Região padrão do GCP"
  value       = var.region
}

output "credentials_file" {
  description = "Caminho do arquivo de credenciais validado"
  value       = var.credentials_file
}
