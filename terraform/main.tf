module "auth" {
  source = "./modules/auth"

  project_id       = var.project_id
  region           = var.region
  credentials_file = var.credentials_file
}

provider "google" {
  project     = module.auth.project_id
  region      = module.auth.region
  credentials = module.auth.credentials_file
}

# Second identity, used only to grant IAM roles. It uses Application
# Default Credentials (your own `gcloud auth application-default login`),
# not the service account key above. This keeps two roles apart: the
# service account that Airflow runs as should only USE permissions, never
# GRANT them, not even to itself. A human account does that instead. See
# the README for setup steps.
provider "google" {
  alias   = "iam_admin"
  project = module.auth.project_id
  region  = module.auth.region
}

# Created with iam_admin (your gcloud login), not the automation service
# account. The service account starts with no project-level roles at all
# (see the comments below). A human account creates each resource first,
# then grants the service account only the small, specific access it needs.
module "data_lake_bucket" {
  source = "./modules/gcs_bucket"
  providers = {
    google = google.iam_admin
  }

  project_id = module.auth.project_id
  name       = var.bucket_name
  location   = var.bucket_location

  depends_on = [module.auth]
}

module "raw_data_dataset" {
  source = "./modules/bigquery_dataset"
  providers = {
    google = google.iam_admin
  }

  project_id  = module.auth.project_id
  dataset_id  = "raw_data"
  location    = var.bucket_location
  description = "Landing zone: raw tables exactly as received from source (raw_encounters, ...). Not AI-ready, loaded directly from GCS by Airflow."

  depends_on = [module.auth]
}

module "analytics_dataset" {
  source = "./modules/bigquery_dataset"
  providers = {
    google = google.iam_admin
  }

  project_id  = module.auth.project_id
  dataset_id  = "analytics"
  location    = var.bucket_location
  description = "dbt output: stg_*/fct_*/dim_* models built from raw_data. Clean and typed, no semantic metadata yet."

  depends_on = [module.auth]
}

locals {
  # Same service account the fhir DAG uses (terraform/keys/*.json), so
  # it can run BigQuery load jobs into raw_data.
  ingestion_service_account_email = jsondecode(file(module.auth.credentials_file))["client_email"]
}

# Bucket-level grant: lets the service account read and write objects in
# this one bucket (needed to upload raw files), with no project-wide
# storage role. Applied with iam_admin, since that identity created the
# bucket.
resource "google_storage_bucket_iam_member" "ingestion_bucket_object_admin" {
  provider = google.iam_admin

  bucket = module.data_lake_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.ingestion_service_account_email}"
}

# Dataset-level grant, also applied with iam_admin, since that identity
# created the dataset above. The service account has no access to it
# until this grant.
resource "google_bigquery_dataset_iam_member" "ingestion_raw_data_editor" {
  provider = google.iam_admin

  project    = module.auth.project_id
  dataset_id = module.raw_data_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.ingestion_service_account_email}"
}

# Project-level grant: running a BigQuery load job needs
# roles/bigquery.jobUser at the project level, and that needs
# resourcemanager.projects.setIamPolicy. Applied with iam_admin (your
# gcloud login), not the automation service account. See the comment on
# that provider above.
resource "google_project_iam_member" "ingestion_bigquery_job_user" {
  provider = google.iam_admin

  project = module.auth.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${local.ingestion_service_account_email}"
}

# dbt gets its own identity, separate from the ingestion service account.
#
# The "dbt" DAG runs a third-party image (ghcr.io/dbt-labs/dbt-bigquery)
# that we don't build ourselves. Its job is to read raw_data and write
# analytics, nothing more: no GCS access, no write access to raw_data.
# Reusing the ingestion service account would give a container we don't
# control write access to data it should never touch. Created with
# iam_admin, same as everything else the ingestion service account can't
# grant itself.
resource "google_service_account" "dbt" {
  provider = google.iam_admin

  project      = module.auth.project_id
  account_id   = "dbt-transform"
  display_name = "dbt (transformation): reads raw_data, writes analytics"
}

# Terraform creates this key. It stays out of git the same way
# terraform/keys/*.json already does (terraform/.gitignore: keys/). This
# is fine for local dev. A production setup would use workload identity
# instead of a downloadable key.
resource "google_service_account_key" "dbt" {
  provider = google.iam_admin

  service_account_id = google_service_account.dbt.name
}

resource "local_file" "dbt_key" {
  content         = base64decode(google_service_account_key.dbt.private_key)
  filename        = "${path.module}/keys/dbt-transform-key.json"
  file_permission = "0600"
}

resource "google_bigquery_dataset_iam_member" "dbt_raw_data_viewer" {
  provider = google.iam_admin

  project    = module.auth.project_id
  dataset_id = module.raw_data_dataset.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_analytics_editor" {
  provider = google.iam_admin

  project    = module.auth.project_id
  dataset_id = module.analytics_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_project_iam_member" "dbt_bigquery_job_user" {
  provider = google.iam_admin

  project = module.auth.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt.email}"
}
