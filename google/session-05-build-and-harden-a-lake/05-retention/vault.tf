# Step 8. The Raw zone's Immutable contract, expressed as a mechanism.
#
# A retention policy sets a minimum age before an object may be deleted,
# overwritten, or archived. It applies to every object in the bucket and it
# applies to the person who wrote it. Step 8 attempts a delete and reads the
# refusal; step 12 attempts a destroy and reads the same refusal from the other
# side of the term.
#
# One hour rather than the seven years on slide 22, for one reason: an hour
# outlives the class and can be cleared afterwards. A locked policy could not
# be cleared at all, which is the difference Bucket Lock makes and the reason
# step 8 shows where the button is without pressing it.
resource "google_storage_bucket" "vault" {
  name          = "dsba6190-vault-${var.name_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  retention_policy {
    retention_period = 3600
    # is_locked defaults to false. Setting it true is irreversible, survives
    # terraform destroy, and would leave this bucket in the project until the
    # retention period expires. Do not set it.
  }

  labels = {
    environment = "demo"
    zone        = "raw"
    owner       = "data-platform"
    course      = "dsba6190"
  }

  force_destroy = true
}

output "vault_bucket" {
  value = google_storage_bucket.vault.url
}
