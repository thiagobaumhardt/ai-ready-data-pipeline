output "name" {
  description = "Nome do bucket criado"
  value       = google_storage_bucket.this.name
}

output "url" {
  description = "URL gs:// do bucket"
  value       = google_storage_bucket.this.url
}

output "self_link" {
  description = "Self link do bucket na API do GCP"
  value       = google_storage_bucket.this.self_link
}
