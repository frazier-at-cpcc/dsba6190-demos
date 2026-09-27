#!/usr/bin/env bash
# Step 10 · Partition pruning, measured · slide 15 · 6 minutes
#
# Uploads 10 daily partitions under curated/events/dt=YYYY-MM-DD/, applies BigQuery
# Hive-partitioned external table, and demonstrates 10x byte scan savings via partition pruning.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 10 · Partition pruning, measured\033[0m"
echo -e "\033[1;32m    Slide 15 · 6 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Uploading partitioned events to Curated zone...\033[0m"
gcloud storage cp -r sample/events "gs://dsba6190-lake-$SUFFIX/curated/" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls gs://dsba6190-lake-$SUFFIX/curated/events/\033[0m"
gcloud storage ls "gs://dsba6190-lake-$SUFFIX/curated/events/" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 2. Staging and applying Hive-partitioned external table (events.tf)...\033[0m"
cp events.tf.staged events.tf
echo "$ cat events.tf"
cat events.tf
terraform apply $AUTO_APPROVE

JOB_ALL="dsba6190-$SUFFIX-all-$(date +%s)"
JOB_ONE="dsba6190-$SUFFIX-one-$(date +%s)"

echo -e "\n\033[1;34m>>> 3. Querying ALL partitions (Job: $JOB_ALL)...\033[0m"
bq --project_id="$PROJECT" query --use_legacy_sql=false --nouse_cache --job_id="$JOB_ALL" \
  "SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading FROM \`$PROJECT.dsba6190_lake_$SUFFIX.events\`"

echo -e "\n\033[1;34m>>> 4. Querying ONE partition with WHERE dt = '2026-09-17' (Job: $JOB_ONE)...\033[0m"
bq --project_id="$PROJECT" query --use_legacy_sql=false --nouse_cache --job_id="$JOB_ONE" \
  "SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading FROM \`$PROJECT.dsba6190_lake_$SUFFIX.events\` WHERE dt = '2026-09-17'"

echo -e "\n\033[1;34m$ bq show -j $JOB_ALL\033[0m"
bq --project_id="$PROJECT" show -j "$JOB_ALL"

echo -e "\n\033[1;34m$ bq show -j $JOB_ONE\033[0m"
bq --project_id="$PROJECT" show -j "$JOB_ONE"

echo -e "\n\033[1;33m[Teaching note]\033[0m Compare Bytes Processed:"
echo "  - All partitions: 1,600,000 bytes (all 10 files scanned)"
echo "  - dt = '2026-09-17': 160,000 bytes (exactly 1 file scanned = 10x savings)"
echo "  dt is not a column in the parquet files; it was derived purely from the path prefix."
echo -e "\n\033[1;32m>>> Step 10 complete.\033[0m"
