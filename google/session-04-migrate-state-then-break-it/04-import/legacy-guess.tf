# Step 8, first draft. This is what a reasonable person writes from memory
# before looking at the bucket. Import needs an address to attach to, so the
# block has to exist before `terraform import` runs, and nothing checks that
# the block is right.
resource "google_storage_bucket" "legacy" {
  name     = "dsba6190-legacy-${var.name_suffix}"
  location = "US-EAST1"
}
