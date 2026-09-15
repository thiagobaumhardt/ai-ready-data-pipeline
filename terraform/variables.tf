variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
  default     = "healthcare-460623"
}

variable "region" {
  description = "Região padrão do GCP"
  type        = string
  default     = "us-central1"
}

variable "credentials_file" {
  description = "Caminho para o arquivo JSON da service account"
  type        = string
  default     = "./keys/healthcare-460623-29937ab2eddf.json"
}

variable "bucket_name" {
  description = "Nome do bucket do data lake (deve ser globalmente único no GCS)"
  type        = string
  default     = "data-lake"
}

variable "bucket_location" {
  description = "Localização do bucket do data lake"
  type        = string
  default     = "US"
}
