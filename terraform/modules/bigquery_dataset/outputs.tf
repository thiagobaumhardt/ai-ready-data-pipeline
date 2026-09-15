output "dataset_id" {
  description = "ID of the created BigQuery dataset"
  value       = google_bigquery_dataset.this.dataset_id
}

output "self_link" {
  description = "Self link of the dataset in the GCP API"
  value       = google_bigquery_dataset.this.self_link
}
