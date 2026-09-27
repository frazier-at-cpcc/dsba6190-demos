# Step 2. The governed bucket, added beside the ungoverned one
# rather than replacing it, so step 4 can run the same command against both.
#
# Read it argument by argument against a governance checklist. Four of the
# five controls are here. The fifth, a retention policy,
# arrives in step 8 on its own bucket, because a retention policy on the lake
# would make steps 5 and 12 impossible.
resource "google_storage_bucket" "lake" {
  name          = "dsba6190-lake-${var.name_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  # One bucket policy, no per-object ACLs.
  uniform_bucket_level_access = true

  # A refusal rather than a warning. Step 4 shows the refusal.
  public_access_prevention = "enforced"

  # The undo for overwrite and delete. Step 5 uses it.
  versioning {
    enabled = true
  }

  # Cost attribution. A bucket nobody can bill to is a bucket nobody owns.
  labels = {
    environment = "demo"
    zone        = "lake"
    owner       = "data-platform"
    course      = "dsba6190"
  }

  # True on every bucket here so that step 12 fails for exactly one reason,
  # and that reason is the retention policy. Session 4 already made the
  # argument for leaving it false in a real repository.
  force_destroy = true
}

output "lake_bucket" {
  value = google_storage_bucket.lake.url
}
