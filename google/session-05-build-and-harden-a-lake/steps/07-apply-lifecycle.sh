#!/usr/bin/env bash
# Step 7 · The lifecycle rule that nothing runs tonight · slide 11 · 4 minutes
#
# Replaces lake.tf with lifecycle rules (Nearline at 30 days, Archive at 365 days),
# runs plan and apply (in-place update), and inspects lifecycle configuration.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 7 · The lifecycle rule that nothing runs tonight\033[0m"
echo -e "\033[1;32m    Slide 11 · 4 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m$ cp lake.tf.lifecycle lake.tf\033[0m"
cp lake.tf.lifecycle lake.tf

echo -e "\n\033[1;34m$ terraform plan\033[0m"
terraform plan

echo -e "\n\033[1;34m$ terraform apply $AUTO_APPROVE\033[0m"
terraform apply $AUTO_APPROVE

echo -e "\n\033[1;34m$ gcloud storage buckets describe gs://dsba6190-lake-$SUFFIX --format=\"yaml(name,lifecycle_config)\"\033[0m"
gcloud storage buckets describe "gs://dsba6190-lake-$SUFFIX" \
  --project "$PROJECT" \
  --format="yaml(name,lifecycle_config)"

echo -e "\n\033[1;33m[Teaching note]\033[0m Nothing moves tonight. Cloud Storage evaluates lifecycle asynchronously once daily."
echo "Rule encodes access pattern: Nearline at 30 days, Archive at 365 days."
echo -e "\n\033[1;32m>>> Step 7 complete.\033[0m"
