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

# Second identity, used only to grant IAM. Authenticates via Application
# Default Credentials (your own `gcloud auth application-default login`),
# not the automation service account key above. This is the standard
# "bootstrap identity vs. workload identity" split: the service account
# that Airflow runs as should only ever USE permissions, never GRANT them
# (including to itself) - so IAM changes are applied by a human/admin
# principal instead. See README prerequisites.
provider "google" {
  alias   = "iam_admin"
  project = module.auth.project_id
  region  = module.auth.region
}

# Created via iam_admin (your gcloud login), not the automation service
# account: the service account is granted no standing project-level roles
# at all (see comments below) - every resource it needs is bootstrapped by
# a human/admin identity, which then grants the service account only the
# narrow, resource-scoped access it needs to operate afterwards.
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

locals {
  # Same service account Airflow's fhir_ingestion DAG authenticates with
  # (terraform/keys/*.json), so it can run BigQuery load jobs into raw_data.
  ingestion_service_account_email = jsondecode(file(module.auth.credentials_file))["client_email"]
}

# Bucket-level grant: lets the service account read/write objects in this
# one bucket (what fhir_ingestion needs to upload raw files) without any
# project-wide storage role. Applied via iam_admin since the bucket above
# was created by that identity.
resource "google_storage_bucket_iam_member" "ingestion_bucket_object_admin" {
  provider = google.iam_admin

  bucket = module.data_lake_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.ingestion_service_account_email}"
}

# Dataset-level grant: applied via iam_admin too, since the dataset above was
# created by that identity, not the service account (which has no standing
# access to it until granted here).
resource "google_bigquery_dataset_iam_member" "ingestion_raw_data_editor" {
  provider = google.iam_admin

  project    = module.auth.project_id
  dataset_id = module.raw_data_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.ingestion_service_account_email}"
}

# Project-level grant: running a BigQuery load job needs roles/bigquery.jobUser
# at the project level, which requires resourcemanager.projects.setIamPolicy.
# Applied via the iam_admin provider (your own gcloud login), not the
# automation service account - see the comment on that provider above.
resource "google_project_iam_member" "ingestion_bigquery_job_user" {
  provider = google.iam_admin

  project = module.auth.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${local.ingestion_service_account_email}"
}
