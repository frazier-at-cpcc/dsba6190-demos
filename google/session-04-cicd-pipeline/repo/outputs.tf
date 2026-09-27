output "lake_bucket" {
  value = google_storage_bucket.lake.name
}

output "scratch_bucket" {
  value = google_storage_bucket.scratch.name
}
