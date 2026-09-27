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

# Step 6. One module. Two invocations. One source of truth.
module "dev_lake" {
  source = "./modules/data-lake"

  environment   = "dev"
  name_suffix   = var.bucket_suffix
  storage_class = "STANDARD"
  owner         = "data-platform"
}

module "prod_lake" {
  source = "./modules/data-lake"

  environment   = "prod"
  name_suffix   = var.bucket_suffix
  storage_class = "NEARLINE"
  owner         = "data-platform"
}

output "dev_bucket" {
  value = module.dev_lake.bucket_url
}

output "prod_bucket" {
  value = module.prod_lake.bucket_url
}
