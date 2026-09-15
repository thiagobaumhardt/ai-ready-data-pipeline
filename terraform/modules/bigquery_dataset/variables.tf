variable "project_id" {
  description = "GCP project ID where the dataset will be created"
  type        = string
}

variable "dataset_id" {
  description = "BigQuery dataset ID (e.g. raw_data)"
  type        = string
}

variable "location" {
  description = "Dataset location (must match the source bucket's region for load jobs to work)"
  type        = string
  default     = "US"
}

variable "description" {
  description = "Dataset description"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels applied to the dataset"
  type        = map(string)
  default     = {}
}
