#!/usr/bin/env bash
# Step 1 · Read the governed bucket before anything runs · slide 26 · 4 minutes
#
# Copies lake.tf.staged to lake.tf, displays the 4 governance controls,
# and executes `terraform plan` to show the review artifact before creating.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 1 · Read the governed bucket before anything runs\033[0m"
echo -e "\033[1;32m    Slide 26 · 4 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m$ cp lake.tf.staged lake.tf\033[0m"
cp lake.tf.staged lake.tf

echo -e "\n\033[1;34m$ cat lake.tf\033[0m"
cat lake.tf

echo -e "\n\033[1;33m[Teaching note]\033[0m Read resource line by line against the governance list:"
echo "  1. uniform_bucket_level_access = true"
echo "  2. public_access_prevention    = \"enforced\""
echo "  3. versioning { enabled = true }"
echo "  4. labels = { environment, zone, owner, course }"
echo "  Absent: retention_policy & lifecycle_rule (arrive later at steps 7 & 8)."

echo -e "\n\033[1;34m$ terraform plan\033[0m"
terraform plan

echo -e "\n\033[1;32m>>> Step 1 complete. Expect: Plan: 1 to add, 0 to change, 0 to destroy.\033[0m"
