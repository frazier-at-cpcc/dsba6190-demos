# Step 9. The same encryption, a different key holder.
#
# Every object in Cloud Storage is already encrypted at rest. This bucket does
# not add encryption. It changes who controls the key, and that is the whole
# of what CMEK buys, as slide 19 says.
#
# The key itself is deliberately not in this configuration. live-setup.sh
# creates the key ring, the key, and the Cloud Storage service agent's binding
# on it before class, for two reasons. IAM propagation on a key takes longer
# than step 9 has, and a Cloud KMS key ring cannot be deleted once created, so
# a resource Terraform destroys should not be one Terraform cannot remove.
resource "google_storage_bucket" "secure" {
  name          = "dsba6190-secure-${var.name_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  encryption {
    default_kms_key_name = var.kms_key
  }

  labels = {
    environment = "demo"
    zone        = "regulated"
    owner       = "data-platform"
    course      = "dsba6190"
  }

  force_destroy = true
}

output "secure_bucket" {
  value = google_storage_bucket.secure.url
}
