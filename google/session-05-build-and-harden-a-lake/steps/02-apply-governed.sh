#!/usr/bin/env bash
# Step 2 · Apply. Two buckets, one governed · slide 26 · 5 minutes
#
# Applies the governed bucket and describes both buckets side by side
# to show enforced governance vs inherited/ungoverned defaults.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 2 · Apply. Two buckets, one governed\033[0m"
echo -e "\033[1;32m    Slide 26 · 5 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m$ terraform apply $AUTO_APPROVE\033[0m"
terraform apply $AUTO_APPROVE

echo -e "\n\033[1;34m$ gcloud storage buckets describe gs://dsba6190-lake-$SUFFIX (Governed Bucket)\033[0m"
gcloud storage buckets describe "gs://dsba6190-lake-$SUFFIX" \
  --project "$PROJECT" \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"

echo -e "\n\033[1;34m$ gcloud storage buckets describe gs://dsba6190-staging-$SUFFIX (Ungoverned Bucket)\033[0m"
gcloud storage buckets describe "gs://dsba6190-staging-$SUFFIX" \
  --project "$PROJECT" \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"

echo -e "\n\033[1;33m[Teaching note]\033[0m Compare outputs side by side:"
echo "  - Governed bucket: labels present, public_access_prevention: ENFORCED, uniform_bucket_level_access: TRUE, versioning: TRUE."
echo "  - Ungoverned bucket: NO labels, public_access_prevention: INHERITED (means OFF), uniform_bucket_level_access: FALSE."
echo -e "\n\033[1;32m>>> Step 2 complete.\033[0m"
