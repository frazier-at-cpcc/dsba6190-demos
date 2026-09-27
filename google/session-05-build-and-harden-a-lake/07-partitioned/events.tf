# Step 10. The same 200,000 rows again, laid out as ten daily prefixes instead
# of one object, and read through hive partitioning.
#
# `dt` is not a column in any of these files. It is a directory name, and
# `source_uri_prefix` is the line that tells BigQuery where the key-equals-value
# pairs begin. Everything to the right of that prefix becomes a partitioning
# column. That is the whole of the Hive partitioning convention, and step 10
# measures what it buys.
resource "google_bigquery_table" "events" {
  dataset_id          = google_bigquery_dataset.lake.dataset_id
  table_id            = "events"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["${google_storage_bucket.lake.url}/curated/events/*"]

    hive_partitioning_options {
      mode = "AUTO"

      # Everything after this prefix is read as partitioning keys. Point at the
      # directory above `dt=`, not at the objects.
      source_uri_prefix = "${google_storage_bucket.lake.url}/curated/events/"
    }
  }
}
