output "name" {
  description = "Name of the created bucket"
  value       = google_storage_bucket.this.name
}

output "url" {
  description = "gs:// URL of the bucket"
  value       = google_storage_bucket.this.url
}

output "self_link" {
  description = "Self link of the bucket in the GCP API"
  value       = google_storage_bucket.this.self_link
}
