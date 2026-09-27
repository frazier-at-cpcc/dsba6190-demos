#!/usr/bin/env bash
# Step 4 · Make it public. Twice · slide 25 · 5 minutes
#
# Demonstrates public exposure on the ungoverned staging bucket, anonymous curl access,
# and contrasts that with HTTP 412 (PAP refusal) and HTTP 400 (UBLA refusal) on the lake.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 4 · Make it public. Twice\033[0m"
echo -e "\033[1;32m    Slide 25 · 5 minutes · Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Adding allUsers objectViewer binding to ungoverned staging bucket...\033[0m"
gcloud storage buckets add-iam-policy-binding "gs://dsba6190-staging-$SUFFIX" \
  --project "$PROJECT" \
  --member=allUsers --role=roles/storage.objectViewer

echo -e "\n\033[1;34m>>> 2. Uploading confidential defect report _qc.csv to staging bucket...\033[0m"
printf 'plant,serial,defect\ncharlotte,SN-88213,hairline crack\n' > _qc.csv
gcloud storage cp _qc.csv "gs://dsba6190-staging-$SUFFIX/qc.csv" --project "$PROJECT"

echo -e "\n\033[1;34m$ curl https://storage.googleapis.com/dsba6190-staging-$SUFFIX/qc.csv\033[0m"
for i in $(seq 1 12); do
  body="$(curl -s "https://storage.googleapis.com/dsba6190-staging-$SUFFIX/qc.csv" || true)"
  if [[ "$body" == *"hairline"* ]]; then
    echo "$body"
    echo -e "\033[1;31m[DANGER]\033[0m Anonymous internet fetch succeeded without credentials!"
    break
  fi
  echo "Waiting for IAM propagation ($i/12)..."
  sleep 2
done

echo -e "\n\033[1;34m>>> 3. Attempting the SAME allUsers binding on the GOVERNED lake bucket...\033[0m"
echo "$ gcloud storage buckets add-iam-policy-binding gs://dsba6190-lake-$SUFFIX --member=allUsers ..."
set +e
gcloud storage buckets add-iam-policy-binding "gs://dsba6190-lake-$SUFFIX" \
  --project "$PROJECT" \
  --member=allUsers --role=roles/storage.objectViewer 2>&1
PAP_CODE=$?
set -e
echo -e "\033[1;33m[Teaching note]\033[0m Notice HTTP 412 Precondition Failed. Public access prevention is a hard refusal, not a warning."

echo -e "\n\033[1;34m>>> 4. Attempting per-object ACL grant on the GOVERNED lake bucket...\033[0m"
echo "$ gcloud storage objects update gs://dsba6190-lake-$SUFFIX/raw/... --add-acl-grant=entity=allUsers,role=READER"
set +e
gcloud storage objects update "gs://dsba6190-lake-$SUFFIX/raw/readings/readings.csv" \
  --project "$PROJECT" \
  --add-acl-grant=entity=allUsers,role=READER 2>&1
UBLA_CODE=$?
set -e
echo -e "\033[1;33m[Teaching note]\033[0m Notice HTTP 400 Bad Request. UBLA completely disables per-object ACL bypasses."

echo -e "\n\033[1;34m>>> 5. Revoking public exposure on the staging bucket...\033[0m"
gcloud storage buckets remove-iam-policy-binding "gs://dsba6190-staging-$SUFFIX" \
  --project "$PROJECT" \
  --member=allUsers --role=roles/storage.objectViewer

echo -e "\n\033[1;32m>>> Step 4 complete. Exposure successfully revoked.\033[0m"
