variable "project_id" {
  description = "ID do projeto GCP onde o bucket será criado"
  type        = string
}

variable "name" {
  description = "Nome do bucket (deve ser globalmente único no GCS)"
  type        = string
  default     = "data-lake"
}

variable "location" {
  description = "Localização/região do bucket"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Classe de armazenamento do bucket"
  type        = string
  default     = "STANDARD"
}

variable "force_destroy" {
  description = "Permite destruir o bucket mesmo que contenha objetos (cuidado em produção)"
  type        = bool
  default     = false
}

variable "uniform_bucket_level_access" {
  description = "Usa controle de acesso uniforme (recomendado pelo Google) em vez de ACLs por objeto"
  type        = bool
  default     = true
}

variable "versioning_enabled" {
  description = "Habilita versionamento de objetos no bucket"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels aplicadas ao bucket"
  type        = map(string)
  default     = {}
}
