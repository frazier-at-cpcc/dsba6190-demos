# Step 8, second draft, written from what the plan reported rather than from
# memory. The plan is now the documentation of a bucket nobody wrote down.
resource "google_storage_bucket" "legacy" {
  name          = "dsba6190-legacy-${var.name_suffix}"
  location      = "US-CENTRAL1"
  storage_class = "NEARLINE"
  force_destroy = false

  labels = {
    environment = "prod"
    owner       = "unknown"
  }
}
