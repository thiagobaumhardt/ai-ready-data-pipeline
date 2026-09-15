terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# The `provider "google"` block lives in the root module (Terraform restriction:
# providers can't be configured inside child modules). This module only validates
# and centralizes the authentication data for the root to pass to the provider.
