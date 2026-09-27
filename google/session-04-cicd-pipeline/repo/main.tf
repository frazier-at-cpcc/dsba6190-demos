locals {
  labels = merge(
    {
      owner      = "dsba6190"
      env        = var.env
      managed-by = "terraform"
    },
    var.extra_labels,
  )
}

# The lake holds data. Destroying it is a deliberate act, never a side effect
# of a refactor, so prevent_destroy makes Terraform refuse.
resource "google_storage_bucket" "lake" {
  name                        = "${var.project_id}-cicd-lake"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Scratch holds nothing worth keeping. It exists so the pipeline has something
# safe to change, rename, and replace in front of a room.
resource "google_storage_bucket" "scratch" {
  name                        = "${var.project_id}-cicd-scratch"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels                      = local.labels
}
