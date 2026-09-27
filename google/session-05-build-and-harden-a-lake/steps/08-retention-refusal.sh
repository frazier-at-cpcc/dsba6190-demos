#!/usr/bin/env bash
# Step 8 · Retention, and a delete that fails
#
# Provisions a vault bucket with a 3600-second retention policy, uploads an incident record,
# and demonstrates the platform HTTP 403 refusal on attempted deletion.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 8 · Retention, and a delete that fails\033[0m"
echo -e "\033[1;32m    Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Staging and applying vault bucket with retention policy...\033[0m"
cp vault.tf.staged vault.tf
terraform apply $AUTO_APPROVE

echo -e "\n\033[1;34m$ gcloud storage buckets describe gs://dsba6190-vault-$SUFFIX --format=\"yaml(name,retention_policy)\"\033[0m"
gcloud storage buckets describe "gs://dsba6190-vault-$SUFFIX" \
  --project "$PROJECT" \
  --format="yaml(name,retention_policy)"

echo -e "\n\033[1;34m>>> 2. Writing and uploading critical incident record _incident.csv...\033[0m"
printf 'incident,plant,reading,recorded_at\n1,charlotte,231.4,2026-09-17T19:04:11Z\n' > _incident.csv
gcloud storage cp _incident.csv "gs://dsba6190-vault-$SUFFIX/raw/incident.csv" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 3. Attempting to delete retention-protected incident record...\033[0m"
echo "$ gcloud storage rm gs://dsba6190-vault-$SUFFIX/raw/incident.csv"
set +e
gcloud storage rm "gs://dsba6190-vault-$SUFFIX/raw/incident.csv" --project "$PROJECT" 2>&1
DELETE_CODE=$?
set -e

echo -e "\n\033[1;33m[Note]\033[0m Notice HTTP 403: Object is subject to bucket's retention policy and cannot be deleted or overwritten."
echo "Raw zone immutability is enforced by infrastructure, not documented by convention."
echo -e "\n\033[1;32m>>> Step 8 complete.\033[0m"
