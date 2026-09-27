# The interface others consume. This is the module's return value.
output "bucket_name" {
  value       = google_storage_bucket.raw.name
  description = "Name of the raw-zone bucket."
}

output "bucket_url" {
  value       = google_storage_bucket.raw.url
  description = "gs:// URL of the raw-zone bucket."
}

output "labels" {
  value       = local.labels
  description = "The labels applied, after the module enforces its standard keys."
}
