# Step 7. The same governed bucket, now carrying the two lifecycle rules
# from slide 9. This file replaces the one step 2 applied, so the plan is a
# single in-place update and the diff is exactly the two blocks added.
#
# Step 2. The governed bucket from slide 22, added beside the ungoverned one
# rather than replacing it, so step 4 can run the same command against both.
#
# Read it argument by argument against the governance list from Concept
# Block 2. Four of the five controls are here. The fifth, a retention policy,
# arrives in step 8 on its own bucket, because a retention policy on the lake
# would make steps 5 and 12 impossible.
resource "google_storage_bucket" "lake" {
  name          = "dsba6190-lake-${var.name_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  # One bucket policy, no per-object ACLs. Slide 21's last bullet.
  uniform_bucket_level_access = true

  # A refusal rather than a warning. Step 4 reads the refusal out loud.
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

  # Step 7. Classify by access pattern, not by age, and then let the rule do
  # the moving. Nothing moves tonight: Cloud Storage evaluates lifecycle rules
  # asynchronously, roughly once a day, and the youngest object here is minutes
  # old. The rule is the artifact, not the transition.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # True on every bucket here so that step 12 fails for exactly one reason,
  # and that reason is the retention policy. Session 4 already made the
  # argument for leaving it false in a real repository.
  force_destroy = true
}

output "lake_bucket" {
  value = google_storage_bucket.lake.url
}
