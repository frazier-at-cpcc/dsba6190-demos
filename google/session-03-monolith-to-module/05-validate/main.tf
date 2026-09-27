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
  type = string
}

variable "bucket_suffix" {
  type = string
}

# Step 8. The module now validates its inputs and enforces its labels.
# The dev caller tries to set environment itself. The module overrules it.
module "dev_lake" {
  source = "./modules/data-lake"

  environment   = "dev"
  name_suffix   = var.bucket_suffix
  storage_class = "STANDARD"
  owner         = "data-platform"
  extra_labels = {
    environment = "sandbox"
    team        = "fleet-dashboards"
  }
}

module "prod_lake" {
  source = "./modules/data-lake"

  environment   = "prod"
  name_suffix   = var.bucket_suffix
  storage_class = "NEARLINE"
  owner         = "data-platform"
  extra_labels = {
    team = "fleet-dashboards"
  }
}

output "dev_bucket" {
  value = module.dev_lake.bucket_url
}

output "prod_bucket" {
  value = module.prod_lake.bucket_url
}

output "dev_labels" {
  value       = module.dev_lake.labels
  description = "The labels the dev bucket actually carries."
}
