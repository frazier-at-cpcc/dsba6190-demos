#!/usr/bin/env bash
# Step 3 · The four zones, and the object that lands in raw · slide 12 · 4 minutes
#
# Creates five zone prefixes using sentinel objects, uploads the raw readings CSV,
# and verifies that prefixes in object storage are flat keys, not POSIX directories.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 3 · The four zones, and the object that lands in raw\033[0m"
echo -e "\033[1;32m    Slide 12 · 4 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> Creating 5 zone sentinel objects (raw, validated, curated, archive, quarantine)...\033[0m"
for z in raw validated curated archive quarantine; do
  printf 'zone: %s\ncontract: see lecture 5, slide 12\n' "$z" > _zone.txt
  gcloud storage cp _zone.txt "gs://dsba6190-lake-$SUFFIX/$z/_ZONE" --project "$PROJECT"
done

echo -e "\n\033[1;34m$ gcloud storage ls gs://dsba6190-lake-$SUFFIX\033[0m"
gcloud storage ls "gs://dsba6190-lake-$SUFFIX" --project "$PROJECT"

echo -e "\n\033[1;33m[Teaching note]\033[0m Five prefixes and zero directories. Prefixes only exist because objects live under them."

echo -e "\n\033[1;34m>>> Uploading sample/readings.csv to gs://dsba6190-lake-$SUFFIX/raw/readings/readings.csv...\033[0m"
gcloud storage cp sample/readings.csv "gs://dsba6190-lake-$SUFFIX/raw/readings/readings.csv" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage ls -r gs://dsba6190-lake-$SUFFIX/raw/\033[0m"
gcloud storage ls -r "gs://dsba6190-lake-$SUFFIX/raw/" --project "$PROJECT"

echo -e "\n\033[1;33m[Teaching note]\033[0m 200,000 rows landed in Raw untouched. Raw contract: immutable, raw fidelity, reprocessible."
echo -e "\n\033[1;32m>>> Step 3 complete.\033[0m"
