# Step 6. Two external tables over the same 200,000 readings, one CSV and one
# Parquet, so the format argument is settled by a measurement rather than by
# assertion.
#
# An external table reads the objects where they already sit. Nothing is copied
# into BigQuery, so the numbers in step 6 are the bytes BigQuery read out of
# Cloud Storage.
resource "google_bigquery_dataset" "lake" {
  dataset_id  = "dsba6190_lake_${var.name_suffix}"
  location    = "US"
  description = "Session 5 live demo. External tables over the lake bucket."

  labels = {
    environment = "demo"
    course      = "dsba6190"
  }

  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "readings_csv" {
  dataset_id          = google_bigquery_dataset.lake.dataset_id
  table_id            = "readings_csv"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "CSV"
    source_uris   = ["${google_storage_bucket.lake.url}/raw/readings/readings.csv"]

    csv_options {
      quote             = "\""
      skip_leading_rows = 1
    }
  }
}

resource "google_bigquery_table" "readings_parquet" {
  dataset_id          = google_bigquery_dataset.lake.dataset_id
  table_id            = "readings_parquet"
  deletion_protection = false

  # Parquet carries its own schema, so there is nothing to detect and nothing
  # to declare.
  external_data_configuration {
    autodetect    = true
    source_format = "PARQUET"
    source_uris   = ["${google_storage_bucket.lake.url}/curated/readings/readings.parquet"]
  }
}
