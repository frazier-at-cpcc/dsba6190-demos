# The body. A caller should never need to read this.
locals {
  enforced = {
    environment         = var.environment
    owner               = var.owner
    cost-center         = "dsba6190"
    data-classification = "internal"
  }
  labels = merge(var.extra_labels, local.enforced)
}

resource "google_storage_bucket" "raw" {
  name          = "dsba6190-${var.environment}-raw-${var.name_suffix}"
  location      = var.location
  storage_class = var.storage_class

  uniform_bucket_level_access = true

  # Control 2. A bucket holding objects will not delete.
  force_destroy = var.force_destroy

  labels = local.labels

  # prevent_destroy is left out so the demonstration ends in one teardown.
  # A production module keeps it.
}
