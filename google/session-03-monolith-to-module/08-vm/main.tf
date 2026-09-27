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

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "vm_environment" {
  type    = string
  default = "prod"
}

# The three lakes from step 10, unchanged.
locals {
  # One map. Each key is an environment.
  environments = {
    dev  = { storage_class = "STANDARD" }
    test = { storage_class = "STANDARD" }
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

# Step 11. The Lab 3 VM, behind a five-input module interface.
module "trips_vm" {
  source = "./modules/vm"

  name         = "dsba6190-trips-vm-${var.bucket_suffix}"
  environment  = var.vm_environment
  zone         = "us-east1-b"
  machine_type = var.machine_type
  owner        = "data-platform"
}

output "vm" {
  value = module.trips_vm.summary
}
