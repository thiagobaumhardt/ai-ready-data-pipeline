variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "healthcare-460623"
}

variable "region" {
  description = "Default GCP region"
  type        = string
  default     = "us-central1"
}

variable "credentials_file" {
  description = "Path to the service account JSON key file"
  type        = string
  default     = "./keys/healthcare-460623-29937ab2eddf.json"
}

variable "bucket_name" {
  description = "Name of the data lake bucket (must be globally unique in GCS)"
  type        = string
  default     = "data-lake"
}

variable "bucket_location" {
  description = "Location of the data lake bucket"
  type        = string
  default     = "US"
}
