#!/usr/bin/env bash
# Step 5 · Versioning is the undo · slide 24 · 6 minutes
#
# Demonstrates object versioning: overwriting an object does not destroy history,
# deleting an object adds a delete marker, and any prior generation can be restored.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 5 · Versioning is the undo\033[0m"
echo -e "\033[1;32m    Slide 24 · 6 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Creating and uploading manifest v1 (200,000 rows)...\033[0m"
printf '{"rows": 200000, "written_by": "nightly-ingest", "status": "complete"}\n' > _manifest.json
gcloud storage cp _manifest.json "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

GEN_GOOD="$(gcloud storage objects describe "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" \
  --project "$PROJECT" --format='value(generation)')"
echo -e "Captured generation ID: \033[1;36m$GEN_GOOD\033[0m"

echo -e "\n\033[1;34m>>> 2. Corrupting/overwriting with rerun nobody reviewed (0 rows)...\033[0m"
printf '{"rows": 0, "written_by": "the-rerun-nobody-reviewed", "status": "complete"}\n' > _manifest.json
gcloud storage cp _manifest.json "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage cat gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json\033[0m"
gcloud storage cat "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls --all-versions --long gs://dsba6190-lake-$SUFFIX/raw/readings/\033[0m"
gcloud storage ls --all-versions --long "gs://dsba6190-lake-$SUFFIX/raw/readings/" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 3. Restoring prior generation #$GEN_GOOD...\033[0m"
gcloud storage cp "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json#$GEN_GOOD" \
  "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage cat gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json (Restored)\033[0m"
gcloud storage cat "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 4. Testing accidental DELETE...\033[0m"
gcloud storage rm "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls (Live objects - manifest gone)\033[0m"
gcloud storage ls "gs://dsba6190-lake-$SUFFIX/raw/readings/" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls --all-versions (Generations survive delete)\033[0m"
gcloud storage ls --all-versions --long "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 5. Restoring after delete from #$GEN_GOOD...\033[0m"
gcloud storage cp "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json#$GEN_GOOD" \
  "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"
gcloud storage cat "gs://dsba6190-lake-$SUFFIX/raw/readings/_manifest.json" --project "$PROJECT"

echo -e "\n\033[1;33m[Teaching note]\033[0m Overwrite moved pointer; delete added tombstone. Neither destroyed bytes."
echo "Cost consequence: Noncurrent versions bill until expired by lifecycle rules."
echo -e "\n\033[1;32m>>> Step 5 complete.\033[0m"
