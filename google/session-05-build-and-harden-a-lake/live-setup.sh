#!/usr/bin/env bash
# Stage the Session 5 live demo. Run this BEFORE class, not during.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Like Session 4 and unlike Session 3, this script applies. It applies exactly
# one thing: the ungoverned bucket the demonstration starts from. Step 2 adds
# the governed one beside it and step 4 runs the same command against both, so
# the ungoverned bucket has to exist before the hour begins.
#
# It also creates the Cloud KMS key ring, the key, and the Cloud Storage
# service agent's binding on that key. Those are out of band on purpose. IAM
# propagation on a key takes longer than step 9 has, and a key ring cannot be
# deleted once created, so it should not be a resource Terraform believes it
# can remove.
#
# It generates the sample data, because 200,000 rows of invented telemetry do
# not belong in a Git repository.
#
# It does NOT destroy anything. capture.sh is the headless recorder and tears
# everything down through an exit trap; this is its opposite. Do not run
# capture.sh in front of a class.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR] [SUFFIX]}"
WORK="${2:-$HOME/dsba6190-live-demo-05}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${3:-${SUFFIX:-86612}}"

REGION="us-east1"
KEYRING="dsba6190-demo"
KEYNAME="lake-cmek"
KEY="projects/$PROJECT/locations/$REGION/keyRings/$KEYRING/cryptoKeys/$KEYNAME"

STAGING_BUCKET="dsba6190-staging-$SUFFIX"
LAKE_BUCKET="dsba6190-lake-$SUFFIX"
VAULT_BUCKET="dsba6190-vault-$SUFFIX"
SECURE_BUCKET="dsba6190-secure-$SUFFIX"
DATASET="dsba6190_lake_$SUFFIX"

say () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }

# ------------------------------------------------------------------- services
# Idempotent and quick when they are already on. Cloud KMS is the one that is
# usually off, and enabling it takes a minute to propagate, which is another
# reason this runs at T minus 30 rather than at 1:30.
say "Services"
for api in storage.googleapis.com bigquery.googleapis.com cloudkms.googleapis.com \
           orgpolicy.googleapis.com; do
  if gcloud services list --enabled --project "$PROJECT" \
        --filter="config.name=$api" --format="value(config.name)" | grep -q .; then
    echo "  already enabled  $api"
  else
    echo "  enabling         $api"
    gcloud services enable "$api" --project "$PROJECT" >/dev/null
  fi
done

# ------------------------------------------------------------------ kms setup
say "Cloud KMS key, and the binding step 9 cannot wait for"
gcloud kms keyrings create "$KEYRING" --location "$REGION" --project "$PROJECT" \
       >/dev/null 2>&1 || echo "  key ring already exists  $KEYRING"
gcloud kms keys create "$KEYNAME" --location "$REGION" --keyring "$KEYRING" \
       --purpose encryption --destroy-scheduled-duration=24h --project "$PROJECT" \
       >/dev/null 2>&1 || echo "  key already exists       $KEYNAME"

# A previous teardown scheduled the version for destruction. Restore it if the
# scheduled-destruction window has not closed, and create a fresh primary
# version if it has.
VERSION="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
             --location "$REGION" --project "$PROJECT" \
             --filter="state=ENABLED" --format="value(name)" --limit=1 | awk -F/ '{print $NF}')"
if [ -z "$VERSION" ]; then
  SCHEDULED="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
                 --location "$REGION" --project "$PROJECT" \
                 --filter="state=DESTROY_SCHEDULED" --format="value(name)" --limit=1 \
                 | awk -F/ '{print $NF}')"
  if [ -n "$SCHEDULED" ]; then
    gcloud kms keys versions restore "$SCHEDULED" --key "$KEYNAME" --keyring "$KEYRING" \
           --location "$REGION" --project "$PROJECT" >/dev/null
    VERSION="$SCHEDULED"
    echo "  restored version         $VERSION"
  else
    VERSION="$(gcloud kms keys versions create --key "$KEYNAME" --keyring "$KEYRING" \
                 --location "$REGION" --project "$PROJECT" --primary \
                 --format="value(name)" | awk -F/ '{print $NF}')"
    echo "  created version          $VERSION"
  fi
else
  echo "  live version             $VERSION"
fi
gcloud kms keys versions enable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
       --location "$REGION" --project "$PROJECT" >/dev/null 2>&1 || true

SERVICE_AGENT="$(gcloud storage service-agent --project "$PROJECT" | tr -d '[:space:]')"
gcloud kms keys add-iam-policy-binding "$KEYNAME" --location "$REGION" \
       --keyring "$KEYRING" --project "$PROJECT" \
       --member "serviceAccount:$SERVICE_AGENT" \
       --role roles/cloudkms.cryptoKeyEncrypterDecrypter >/dev/null
echo "  bound                    $SERVICE_AGENT"

# ------------------------------------------------------------- working dir
say "Working directory"
rm -rf "$WORK"
mkdir -p "$WORK"

cp "$HERE/01-plain/main.tf" "$WORK/main.tf"

cat > "$WORK/terraform.tfvars" <<VARS
project_id  = "$PROJECT"
name_suffix = "$SUFFIX"
region      = "$REGION"
kms_key     = "$KEY"
VARS

# Staged additions, so no step is five minutes of live authoring. Each file
# below is added to the working directory at its own step. Terraform reads
# every .tf file in the directory, so adding one is the whole edit.
cp "$HERE/02-governed/lake.tf"       "$WORK/lake.tf.staged"
cp "$HERE/03-tables/tables.tf"       "$WORK/tables.tf.staged"
cp "$HERE/04-lifecycle/lake.tf"      "$WORK/lake.tf.lifecycle"
cp "$HERE/05-retention/vault.tf"     "$WORK/vault.tf.staged"
cp "$HERE/06-cmek/secure.tf"         "$WORK/secure.tf.staged"
cp "$HERE/07-partitioned/events.tf"  "$WORK/events.tf.staged"
if [ -d "$HERE/steps" ]; then
  cp -r "$HERE/steps" "$WORK/steps"
  chmod +x "$WORK/steps"/*.sh
fi
if [ -d "$HERE/.vscode" ]; then
  cp -r "$HERE/.vscode" "$WORK/.vscode"
fi

say "Sample data"
if python3 -c 'import pyarrow' 2>/dev/null; then
  python3 "$HERE/sample/make-sample.py" "$WORK/sample"
else
  uv run --quiet --with pyarrow python3 "$HERE/sample/make-sample.py" "$WORK/sample"
fi

say "Baseline"
( cd "$WORK" && terraform init -no-color >/dev/null )
( cd "$WORK" && terraform apply -auto-approve -no-color >/dev/null )

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export AUTO_APPROVE="--auto-approve"
cd "$WORK"
ENVEOF

cat <<DONE

  Staged for the live demo, and the baseline is applied.

  Working directory   $WORK
  Project             $PROJECT
  Name suffix         $SUFFIX
  Region              $REGION

  Applied, because step 4 needs an ungoverned bucket to compare against:
    $STAGING_BUCKET   google_storage_bucket.staging

  Created out of band, because a key ring cannot be deleted and IAM
  propagation on a key is slower than step 9:
    $KEY
    version $VERSION, and the Cloud Storage service agent bound on it

  NOT created. The demonstration creates each of these at its own step:
    $LAKE_BUCKET      step 2
    $DATASET   step 6
    $VAULT_BUCKET     step 8
    $SECURE_BUCKET    step 9

  Staged files, each added to the working directory at its step:
    lake.tf.staged      step 2   the governed bucket
    tables.tf.staged    step 6   the dataset and two external tables
    lake.tf.lifecycle   step 7   the same bucket, plus two lifecycle rules
    vault.tf.staged     step 8   the bucket with a retention policy
    secure.tf.staged    step 9   the CMEK bucket
    events.tf.staged    step 10  the hive-partitioned external table

  Sample data, generated rather than committed:
    $WORK/sample/readings.csv
    $WORK/sample/readings.parquet
    $WORK/sample/events/dt=YYYY-MM-DD/part-000.parquet

  Verify now, while there is time to fix it:

      cd $WORK && terraform plan

  Expect: No changes. Your infrastructure matches the configuration.

  Tear down after class. In this order, because the second line fails
  until the first one runs:

      gcloud storage buckets update gs://$VAULT_BUCKET --project $PROJECT --clear-retention-period
      cd $WORK && terraform destroy -auto-approve
      gcloud kms keys versions destroy $VERSION --key $KEYNAME --keyring $KEYRING --location $REGION --project $PROJECT

  Step 12 performs the first two lines in front of the room. Run them again
  after class only if the demonstration stopped before step 12. The third line
  is never part of the demonstration and always has to be run by hand.

  A 404 on a bucket means that step never ran and there is nothing to remove.

  Confirm with:

      gcloud storage ls --project $PROJECT
      bq --project_id=$PROJECT ls

DONE
