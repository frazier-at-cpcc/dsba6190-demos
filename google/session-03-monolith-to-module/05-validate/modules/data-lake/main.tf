# The body. A caller should never need to read this.
locals {
  # The labels every bucket carries, whatever the caller passes.
  enforced = {
    environment         = var.environment
    owner               = var.owner
    cost-center         = "dsba6190"
    data-classification = "internal"
  }

  # merge() keeps the value from the LAST map that sets a key.
  # The enforced map comes last, so a caller cannot override it.
  labels = merge(var.extra_labels, local.enforced)
}

resource "google_storage_bucket" "raw" {
  name          = "dsba6190-${var.environment}-raw-${var.name_suffix}"
  location      = var.location
  storage_class = var.storage_class

  uniform_bucket_level_access = true
  force_destroy               = true

  labels = local.labels
}
