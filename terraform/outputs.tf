output "bucket_name" {
  description = "Nome do bucket do data lake criado"
  value       = module.data_lake_bucket.name
}

output "bucket_url" {
  description = "URL gs:// do bucket do data lake"
  value       = module.data_lake_bucket.url
}
