#!/usr/bin/env bash
# Stage the Session 10 demonstration: read a plan, find the skew.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Provisions what the steps cannot wait for: a bucket holding billing.py, a
# year of Queen City Trip Analytics trips written by the generate batch
# (30,000,000 trips and 5,001 accounts, about two and a half minutes on the
# recorded run), and a BigQuery dataset loaded from the same Parquet for steps 4
# and 8. It runs none of the four join variants. demo.ipynb submits each one
# at its own step.
#
# Run it about five minutes before you start demo.ipynb.
# Applies. Never destroys. The teardown it prints is step 11.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-10}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
REGION="${REGION:-us-central1}"
BUCKET="qc-billing-$SUFFIX"
BASE="gs://$BUCKET"
DATASET="qc_billing_$SUFFIX"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "The API, and private Google access on the default subnet"
gcloud services list --enabled --project "$PROJECT" --filter="config.name=dataproc.googleapis.com" \
       --format="value(config.name)" | grep -q . \
  || gcloud services enable dataproc.googleapis.com --project "$PROJECT" >/dev/null
# A serverless batch has no external IP and still has to reach Cloud Storage.
if [ "$(gcloud compute networks subnets describe default --region "$REGION" --project "$PROJECT" \
          --format='value(privateIpGoogleAccess)')" != "True" ]; then
  gcloud compute networks subnets update default --region "$REGION" --project "$PROJECT" \
    --enable-private-ip-google-access >/dev/null
fi

# The working directory has no spaces in its path, unlike the repository.
rm -rf "${WORK:?}"; mkdir -p "$WORK/eventlogs"
cp "$HERE/stages.py" "$HERE/lib.sh" "$WORK/"

step "The bucket and the job"
gcloud storage buckets create "$BASE" --project "$PROJECT" --location "$REGION" \
  --uniform-bucket-level-access >/dev/null
gcloud storage cp "$HERE/jobs/billing.py" "$BASE/jobs/billing.py" >/dev/null

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export CLOUDSDK_CORE_PROJECT="$PROJECT"
export REGION="$REGION"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export BUCKET="$BUCKET"
export BASE="$BASE"
export DATASET="$DATASET"
export DS="$PROJECT.$DATASET"
source "$WORK/lib.sh"
cd "$WORK"
ENVEOF
# shellcheck disable=SC1091
source "$WORK/env.sh"

step "Generate a year of trips (about two and a half minutes)"
batch gen generate "" 30000000

step "Load the same Parquet into BigQuery"
bq --project_id="$PROJECT" --location=US mk --dataset \
   --description "DSBA 6190 Session 10, Queen City Trip Analytics billing" "$PROJECT:$DATASET" >/dev/null
bq --project_id="$PROJECT" --location=US load --source_format=PARQUET \
   "$PROJECT:$DATASET.trips" "$BASE/data/trips/*.parquet" >/dev/null
bq --project_id="$PROJECT" --location=US load --source_format=PARQUET \
   "$PROJECT:$DATASET.accounts" "$BASE/data/accounts/*.parquet" >/dev/null
READY=$(( $(date +%s) - T0 ))

cat <<DONE

  Staged for the demonstration in $(( READY / 60 )) min $(( READY % 60 )) s. No join variant has run.

  Working directory   $WORK
  Name suffix         $SUFFIX
  Bucket              $BASE      (data/trips, data/accounts, jobs/billing.py)
  Dataset             $PROJECT:$DATASET   (trips, accounts)

  Load the names and the helpers into the shell you will run the steps from:

      source $WORK/env.sh

  NOT run. demo.ipynb submits each of these at its own step:
    baseline    step 1        broadcast   step 2
    salted      step 3        aqe         step 4

  Teardown is step 11, and it is also:
    gcloud storage rm -r gs://$BUCKET --project $PROJECT
    bq --project_id=$PROJECT rm -r -f -d $DATASET
DONE
