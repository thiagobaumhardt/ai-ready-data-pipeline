variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região padrão do GCP"
  type        = string
  default     = "us-central1"
}

variable "credentials_file" {
  description = "Caminho para o arquivo JSON da service account usada para autenticação"
  type        = string

  validation {
    condition     = fileexists(var.credentials_file)
    error_message = "Arquivo de credenciais não encontrado em: ${var.credentials_file}"
  }
}
