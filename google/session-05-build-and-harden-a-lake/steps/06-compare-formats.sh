#!/usr/bin/env bash
# Step 6 · CSV to Parquet. Two arguments, two numbers · slides 18 and 20 · 7 minutes
#
# Compares CSV vs Parquet on raw disk storage size (11.78 MB vs 2.56 MB),
# attaches BigQuery external tables, and proves columnar scan savings (12.3 MB vs 1.6 MB).
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 6 · CSV to Parquet. Two arguments, two numbers\033[0m"
echo -e "\033[1;32m    Slides 18 & 20 · 7 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Uploading sample/readings.parquet to Curated zone...\033[0m"
gcloud storage cp sample/readings.parquet \
  "gs://dsba6190-lake-$SUFFIX/curated/readings/readings.parquet" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls -l (Compare CSV vs Parquet file size)\033[0m"
gcloud storage ls -l \
  "gs://dsba6190-lake-$SUFFIX/raw/readings/readings.csv" \
  "gs://dsba6190-lake-$SUFFIX/curated/readings/readings.parquet" --project "$PROJECT"

echo -e "\n\033[1;33m[Storage Comparison]\033[0m 11.78 MiB (CSV) vs 2.56 MiB (Parquet) = 4.6x smaller on disk."

echo -e "\n\033[1;34m>>> 2. Staging and applying BigQuery external tables (tables.tf)...\033[0m"
cp tables.tf.staged tables.tf
terraform apply $AUTO_APPROVE

JOB_CSV="dsba6190-$SUFFIX-csv-$(date +%s)"
JOB_PARQ="dsba6190-$SUFFIX-parq-$(date +%s)"

echo -e "\n\033[1;34m>>> 3. Querying CSV external table (Job: $JOB_CSV)...\033[0m"
bq --project_id="$PROJECT" query --use_legacy_sql=false --nouse_cache --job_id="$JOB_CSV" \
  "SELECT ROUND(AVG(value), 3) AS mean_reading FROM \`$PROJECT.dsba6190_lake_$SUFFIX.readings_csv\`"

echo -e "\n\033[1;34m>>> 4. Querying Parquet external table (Job: $JOB_PARQ)...\033[0m"
bq --project_id="$PROJECT" query --use_legacy_sql=false --nouse_cache --job_id="$JOB_PARQ" \
  "SELECT ROUND(AVG(value), 3) AS mean_reading FROM \`$PROJECT.dsba6190_lake_$SUFFIX.readings_parquet\`"

echo -e "\n\033[1;34m$ bq show -j $JOB_CSV\033[0m"
bq --project_id="$PROJECT" show -j "$JOB_CSV"

echo -e "\n\033[1;34m$ bq show -j $JOB_PARQ\033[0m"
bq --project_id="$PROJECT" show -j "$JOB_PARQ"

echo -e "\n\033[1;33m[Teaching note]\033[0m Notice Bytes Processed:"
echo "  - CSV:     ~12,348,283 bytes (scanned whole file to read 1 column)"
echo "  - Parquet:  1,600,000 bytes (exactly 200,000 rows * 8 bytes for float64 value column!)"
echo "  Format is not just performance tuning; format is query cost control."
echo -e "\n\033[1;32m>>> Step 6 complete.\033[0m"
