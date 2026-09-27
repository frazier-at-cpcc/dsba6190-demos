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
  region  = var.region
}

variable "project_id" {
  type        = string
  description = "The project the demo resources land in."
}

variable "name_suffix" {
  type        = string
  description = "Random suffix, because the bucket namespace is global."
}

variable "region" {
  type        = string
  description = "One region for every resource, so location is never the variable."
  default     = "us-east1"
}

variable "kms_key" {
  type        = string
  description = "Full resource name of the Cloud KMS key. live-setup.sh creates the key and grants the Cloud Storage service agent on it before step 1, because IAM propagation is slower than step 9."
}

# The bucket somebody made in a hurry, before anyone wrote a governance list.
# Every attribute below is a default that was never chosen. Step 2 puts the
# governed bucket next to it and step 4 shows what the difference buys.
resource "google_storage_bucket" "staging" {
  name          = "dsba6190-staging-${var.name_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  # ACLs still on, so a per-object grant is possible.
  uniform_bucket_level_access = false

  # Nothing above this project enforces anything, so "inherited" is "off".
  public_access_prevention = "inherited"

  # No versioning block. No labels. No retention policy. That is the point.

  force_destroy = true
}

output "staging_bucket" {
  value = google_storage_bucket.staging.url
}
