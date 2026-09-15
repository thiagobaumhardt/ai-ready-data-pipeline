#!/usr/bin/env bash
# Bootstrap completo do projeto: Terraform (GCP) -> Terraform (Airflow em kind) -> dbt.
# Rode a partir da raiz do repositório: ./setup.sh
# Pré-requisito: Docker Desktop rodando (o Airflow sobe num cluster kind local,
# gerenciado direto pelo provider Terraform tehcyx/kind via Docker — não precisa
# instalar o CLI do kind separadamente).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo " 1/3  Terraform: autenticando no GCP e provisionando o data-lake"
echo "=================================================================="
cd "$ROOT_DIR/terraform"

if [ ! -f terraform.tfvars ]; then
  echo "ERRO: terraform/terraform.tfvars não encontrado."
  echo "Copie terraform/terraform.tfvars.example para terraform/terraform.tfvars"
  echo "e preencha project_id / credentials_file com os seus valores antes de continuar."
  exit 1
fi

if [ ! -d keys ] || [ -z "$(ls -A keys 2>/dev/null)" ]; then
  echo "ERRO: nenhuma chave de service account encontrada em terraform/keys/."
  echo "Coloque o JSON da sua service account do GCP em terraform/keys/ antes de continuar."
  exit 1
fi

terraform init -input=false
terraform apply -auto-approve

echo
echo "=================================================================="
echo " 2/3  Airflow: criando o cluster kind e instalando via Helm"
echo "=================================================================="
cd "$ROOT_DIR/terraform/local-airflow"

terraform init -input=false
terraform apply -auto-approve

echo
echo "=================================================================="
echo " 3/3  dbt: instalando dependências do projeto"
echo "=================================================================="
if [ -f "$ROOT_DIR/dbt/dbt_project.yml" ]; then
  cd "$ROOT_DIR/dbt"
  dbt deps
else
  echo "Projeto dbt ainda não criado neste repositório — etapa pulada."
fi

echo
echo "=================================================================="
echo " Setup concluído."
echo "=================================================================="
echo " Airflow UI: http://localhost:8080"
echo "   usuário/senha: cd terraform/local-airflow && terraform output admin_username"
echo "                  cd terraform/local-airflow && terraform output -raw admin_password"
echo
echo " Bucket do data-lake:"
echo "   cd terraform && terraform output bucket_url"
echo
echo " Para derrubar o cluster kind do Airflow e liberar memória:"
echo "   cd terraform/local-airflow && terraform destroy"
