terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-east1"
}

variable "project_id" {
  type        = string
  description = "The project the demo bucket lands in."
}

variable "bucket_suffix" {
  type        = string
  description = "Random suffix so the global bucket namespace does not collide."
}

# Step 4. Storage class STANDARD -> NEARLINE. Terraform updates in place: ~
resource "google_storage_bucket" "raw" {
  name          = "dsba6190-raw-${var.bucket_suffix}"
  location      = "US-EAST1"
  storage_class = "NEARLINE"

  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = "demo"
    owner       = "dsba6190"
  }
}
