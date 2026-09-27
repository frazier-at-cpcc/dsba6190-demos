#!/usr/bin/env bash
# Step 12 · Teardown is a teaching step
#
# Demonstrates that terraform destroy fails against the retention policy,
# clears the retention period via gcloud, re-runs destroy to completion,
# and checks the remaining estate.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"
KEYRING="dsba6190-demo"
KEYNAME="lake-cmek"
REGION="us-east1"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 12 · Teardown is a teaching step\033[0m"
echo -e "\033[1;32m    Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Attempting terraform destroy (Watch for expected retention refusal!)...\033[0m"
set +e
terraform destroy $AUTO_APPROVE
DESTROY_STATUS=$?
set -e

if [ $DESTROY_STATUS -ne 0 ]; then
  echo -e "\n\033[1;33m[Teaching note]\033[0m Destruction failed on the vault bucket as intended!"
  echo "The retention policy protects data even from Terraform destroy."
  echo "Non-atomic destruction: 7 resources were destroyed, 1 survived."
fi

echo -e "\n\033[1;34m>>> 2. Clearing retention period on vault bucket...\033[0m"
gcloud storage buckets update "gs://dsba6190-vault-$SUFFIX" \
  --project "$PROJECT" \
  --clear-retention-period || true

echo -e "\n\033[1;34m>>> 3. Re-running terraform destroy (Now succeeds)...\033[0m"
terraform destroy $AUTO_APPROVE

echo -e "\n\033[1;34m>>> 4. Scheduling Cloud KMS key version destruction (Optional cleanup)...\033[0m"
VERSION="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
  --location "$REGION" --project "$PROJECT" --filter="state=ENABLED" \
  --format="value(name)" --limit=1 | awk -F/ '{print $NF}' || true)"
if [ -n "$VERSION" ]; then
  echo "Scheduling KMS key version $VERSION for destruction..."
  gcloud kms keys versions destroy "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
    --location "$REGION" --project "$PROJECT" || true
fi

echo -e "\n\033[1;34m>>> 5. Final Estate Verification:\033[0m"
echo "$ gcloud storage ls --project $PROJECT"
gcloud storage ls --project "$PROJECT" || echo "  No storage buckets remaining."

echo "$ bq --project_id=$PROJECT ls"
bq --project_id="$PROJECT" ls || echo "  No BigQuery datasets remaining."

echo -e "\n\033[1;32m>>> Step 12 complete. Teardown finished.\033[0m"
