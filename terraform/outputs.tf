output "bucket_name" {
  description = "Name of the created data lake bucket"
  value       = module.data_lake_bucket.name
}

output "bucket_url" {
  description = "gs:// URL of the data lake bucket"
  value       = module.data_lake_bucket.url
}

output "raw_data_dataset_id" {
  description = "ID of the raw_data landing zone BigQuery dataset"
  value       = module.raw_data_dataset.dataset_id
}

output "analytics_dataset_id" {
  description = "ID of the analytics BigQuery dataset (dbt output)"
  value       = module.analytics_dataset.dataset_id
}
