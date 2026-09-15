#!/usr/bin/env bash
# Full project bootstrap: Terraform (GCP) -> Terraform (Airflow on kind) -> dbt.
# Run from the repo root: ./setup.sh
# Prerequisite: Docker Desktop running (Airflow comes up on a local kind
# cluster, managed directly by the Terraform tehcyx/kind provider via Docker,
# no need to install the kind CLI separately).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo " 1/3  Terraform: authenticating with GCP and provisioning the data lake"
echo "=================================================================="
cd "$ROOT_DIR/terraform"

if [ ! -f terraform.tfvars ]; then
  echo "ERROR: terraform/terraform.tfvars not found."
  echo "Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars"
  echo "and fill in project_id / credentials_file with your own values before continuing."
  exit 1
fi

if [ ! -d keys ] || [ -z "$(ls -A keys 2>/dev/null)" ]; then
  echo "ERROR: no service account key found in terraform/keys/."
  echo "Place your GCP service account JSON key in terraform/keys/ before continuing."
  exit 1
fi

if [ ! -f "${HOME:-}/.config/gcloud/application_default_credentials.json" ] \
   && [ ! -f "${APPDATA:-}/gcloud/application_default_credentials.json" ]; then
  echo "ERROR: no Application Default Credentials found."
  echo "This root grants the service account its BigQuery IAM roles using your own"
  echo "gcloud login (not the service account key), so a human with IAM-admin rights"
  echo "applies that change instead of the automation credential granting it to itself."
  echo "Run: gcloud auth application-default login"
  echo "(see 'On IAM: two identities, on purpose' in README.md for why)"
  exit 1
fi

terraform init -input=false
terraform apply -auto-approve

echo
echo "=================================================================="
echo " 2/3  Airflow: creating the kind cluster and installing via Helm"
echo "=================================================================="
cd "$ROOT_DIR/terraform/local-airflow"

terraform init -input=false
terraform apply -auto-approve

echo
echo "=================================================================="
echo " 3/3  dbt: installing project dependencies"
echo "=================================================================="
if [ -f "$ROOT_DIR/dbt/dbt_project.yml" ]; then
  cd "$ROOT_DIR/dbt"
  dbt deps
else
  echo "dbt project not created yet in this repo, skipping this step."
fi

echo
echo "=================================================================="
echo " Setup complete."
echo "=================================================================="
echo " Airflow UI: http://localhost:8080"
echo "   username/password: cd terraform/local-airflow && terraform output admin_username"
echo "                       cd terraform/local-airflow && terraform output -raw admin_password"
echo
echo " Data lake bucket:"
echo "   cd terraform && terraform output bucket_url"
echo
echo " To tear down the Airflow kind cluster and free memory:"
echo "   cd terraform/local-airflow && terraform destroy"
