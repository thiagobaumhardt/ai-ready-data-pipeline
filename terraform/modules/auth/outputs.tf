output "project_id" {
  description = "Authenticated GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "Default GCP region"
  value       = var.region
}

output "credentials_file" {
  description = "Path to the validated credentials file"
  value       = var.credentials_file
}
