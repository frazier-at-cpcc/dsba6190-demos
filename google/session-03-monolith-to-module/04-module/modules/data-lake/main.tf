# The body. A caller should never need to read this.
locals {
  # Labels are enforced here so a caller cannot forget them.
  # This is what makes the Session 14 FinOps analysis possible.
  standard_labels = {
    environment         = var.environment
    owner               = var.owner
    cost-center         = "dsba6190"
    data-classification = "internal"
  }
}

resource "google_storage_bucket" "raw" {
  name          = "dsba6190-${var.environment}-raw-${var.name_suffix}"
  location      = var.location
  storage_class = var.storage_class

  uniform_bucket_level_access = true
  force_destroy               = true

  labels = local.standard_labels

  lifecycle {
    # Guardrail, not a lock. Someone can remove this block.
    # prevent_destroy = true
  }
}
