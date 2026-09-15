module "auth" {
  source = "./modules/auth"

  project_id        = var.project_id
  region            = var.region
  credentials_file  = var.credentials_file
}

provider "google" {
  project     = module.auth.project_id
  region      = module.auth.region
  credentials = module.auth.credentials_file
}

module "data_lake_bucket" {
  source = "./modules/gcs_bucket"

  project_id = module.auth.project_id
  name       = var.bucket_name
  location   = var.bucket_location

  depends_on = [module.auth]
}
