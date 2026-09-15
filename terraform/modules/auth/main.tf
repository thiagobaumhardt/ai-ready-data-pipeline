terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# O bloco `provider "google"` fica no módulo raiz (restrição do Terraform: providers
# não podem ser configurados dentro de módulos filhos). Este módulo apenas valida
# e centraliza os dados de autenticação para o root repassar ao provider.
