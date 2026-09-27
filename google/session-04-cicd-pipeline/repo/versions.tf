terraform {
  required_version = "~> 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.45"
    }
  }

  # Partial configuration. The bucket and prefix arrive from the pipeline as
  # -backend-config flags, because a backend block cannot read variables.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}
