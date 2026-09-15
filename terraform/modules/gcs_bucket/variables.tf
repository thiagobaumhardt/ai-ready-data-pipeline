variable "project_id" {
  description = "GCP project ID where the bucket will be created"
  type        = string
}

variable "name" {
  description = "Bucket name (must be globally unique in GCS)"
  type        = string
  default     = "data-lake"
}

variable "location" {
  description = "Bucket location/region"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Bucket storage class"
  type        = string
  default     = "STANDARD"
}

variable "force_destroy" {
  description = "Allows destroying the bucket even if it still contains objects (careful in production)"
  type        = bool
  default     = false
}

variable "uniform_bucket_level_access" {
  description = "Uses uniform bucket-level access (Google-recommended) instead of per-object ACLs"
  type        = bool
  default     = true
}

variable "versioning_enabled" {
  description = "Enables object versioning on the bucket"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to the bucket"
  type        = map(string)
  default     = {}
}
