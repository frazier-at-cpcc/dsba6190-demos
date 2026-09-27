#!/usr/bin/env bash
# Step 9 · CMEK, and crypto-shredding
#
# Deploys a CMEK-encrypted bucket, uploads sensitive data, disables the KMS key version
# to demonstrate crypto-shredding (instant read/write refusal), and re-enables the key.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
SUFFIX="${SUFFIX:-86612}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"
AUTO_APPROVE="${AUTO_APPROVE:---auto-approve}"
KEYRING="dsba6190-demo"
KEYNAME="lake-cmek"
REGION="us-east1"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 9 · CMEK, and crypto-shredding\033[0m"
echo -e "\033[1;32m    Suffix: $SUFFIX\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m>>> 1. Staging and applying CMEK-encrypted secure bucket...\033[0m"
cp secure.tf.staged secure.tf
terraform apply $AUTO_APPROVE

echo -e "\n\033[1;34m>>> 2. Writing and uploading regulated data (_regulated.csv)...\033[0m"
printf 'patient_site,serial,defect\ncharlotte,SN-88213,hairline crack\n' > _regulated.csv
gcloud storage cp _regulated.csv "gs://dsba6190-secure-$SUFFIX/raw/regulated.csv" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage objects describe gs://dsba6190-secure-$SUFFIX/raw/regulated.csv\033[0m"
gcloud storage objects describe "gs://dsba6190-secure-$SUFFIX/raw/regulated.csv" \
  --project "$PROJECT" --format="yaml(name,kms_key)"

echo -e "\n\033[1;34m$ gcloud storage cat gs://dsba6190-secure-$SUFFIX/raw/regulated.csv (Key enabled)\033[0m"
gcloud storage cat "gs://dsba6190-secure-$SUFFIX/raw/regulated.csv" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 3. Disabling Cloud KMS key version (Crypto-shredding)...\033[0m"
VERSION="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
  --location "$REGION" --project "$PROJECT" --filter="state=ENABLED" \
  --format="value(name)" --limit=1 | awk -F/ '{print $NF}')"
VERSION="${VERSION:-1}"
echo "Active key version: $VERSION"

gcloud kms keys versions disable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
  --location "$REGION" --project "$PROJECT"

echo -e "\n\033[1;34m>>> 4. Testing READ with disabled key...\033[0m"
for i in $(seq 1 6); do
  set +e
  body="$(gcloud storage cat "gs://dsba6190-secure-$SUFFIX/raw/regulated.csv" --project "$PROJECT" 2>&1)"
  status=$?
  set -e
  if [[ "$body" == *"KEY_DISABLED"* ]] || [[ "$body" == *"ERROR"* ]]; then
    echo "$body"
    break
  else
    echo "Cached unwrapped key in transit; retrying in 2s ($i/6)..."
    sleep 2
  fi
done

echo -e "\n\033[1;34m>>> 5. Testing WRITE with disabled key (refuses immediately)...\033[0m"
set +e
gcloud storage cp _regulated.csv "gs://dsba6190-secure-$SUFFIX/raw/second.csv" --project "$PROJECT" 2>&1
set -e

echo -e "\n\033[1;33m[Note]\033[0m The ciphertext remains in storage, but reading and writing are completely impossible."
echo "Crypto-shredding destroys key access rather than attempting to track down and scrub every replica."

echo -e "\n\033[1;34m>>> 6. Re-enabling Cloud KMS key version $VERSION...\033[0m"
gcloud kms keys versions enable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
  --location "$REGION" --project "$PROJECT"

echo -e "\n\033[1;34m$ gcloud storage cat gs://dsba6190-secure-$SUFFIX/raw/regulated.csv (Restored)\033[0m"
for i in $(seq 1 6); do
  set +e
  body="$(gcloud storage cat "gs://dsba6190-secure-$SUFFIX/raw/regulated.csv" --project "$PROJECT" 2>&1)"
  status=$?
  set -e
  if [ $status -eq 0 ]; then
    echo "$body"
    break
  fi
  sleep 2
done

echo -e "\n\033[1;32m>>> Step 9 complete. Key re-enabled and data readable again.\033[0m"
