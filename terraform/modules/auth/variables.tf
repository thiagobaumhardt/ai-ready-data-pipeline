variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default GCP region"
  type        = string
  default     = "us-central1"
}

variable "credentials_file" {
  description = "Path to the service account JSON key file used for authentication"
  type        = string

  validation {
    condition     = fileexists(var.credentials_file)
    error_message = "Credentials file not found at: ${var.credentials_file}"
  }
}
