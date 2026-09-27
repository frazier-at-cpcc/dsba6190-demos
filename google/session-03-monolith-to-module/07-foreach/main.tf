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

# Step 10. Environments from one map, not one block each.
locals {
  # One map. Each key is an environment.
  environments = {
    dev  = { storage_class = "STANDARD" }
    prod = { storage_class = "NEARLINE" }
  }
}

module "lake" {
  source   = "./modules/data-lake"
  for_each = local.environments

  environment   = each.key
  name_suffix   = var.bucket_suffix
  storage_class = each.value.storage_class
  owner         = "data-platform"
  extra_labels  = { team = "fleet-dashboards" }
}

# The two buckets already exist under their old addresses.
# moved blocks re-address them in state instead of destroying them.
moved {
  from = module.dev_lake
  to   = module.lake["dev"]
}

moved {
  from = module.prod_lake
  to   = module.lake["prod"]
}

output "buckets" {
  value = { for env, lake in module.lake : env => lake.bucket_url }
}
