#!/usr/bin/env bash
# Stage the Session 6 live demo. Run this BEFORE class, not during.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# This script provisions. Unlike every other session's staging script, most of
# what it does is wait: a Cloud Data Fusion instance is the one resource in this
# course that cannot be created inside the hour it is needed. It creates the
# instance, blocks until the instance reports RUNNING, then builds the bucket,
# the dataset, the sample data and the four pipeline definitions around it.
#
# It does NOT destroy anything, and it does NOT deploy or run a pipeline. The
# hour deploys and runs them, because watching a pipeline being built is the
# demonstration. capture.sh is the headless recorder and tears the estate down
# through an exit trap; this is its opposite.
#
# RUN IT AT T MINUS 60. The rehearsal on 10 September 2026 took 11 minutes and
# 6 seconds from `create` to RUNNING, and the first create attempt aborted in
# three seconds and had to be re-issued. Sixty minutes is the margin for that
# re-issue plus a second one.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-06}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="$(date +%s | tail -c 6)"

REGION="us-central1"
INSTANCE="dsba6190-demo-$SUFFIX"
BUCKET="dsba6190-pos-$SUFFIX"
DATASET="dsba6190_sales_$SUFFIX"
TABLE="sales_validated"

say () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }

# ------------------------------------------------------------------- services
say "Services"
for api in datafusion.googleapis.com dataproc.googleapis.com \
           storage.googleapis.com bigquery.googleapis.com; do
  if gcloud services list --enabled --project "$PROJECT" \
        --filter="config.name=$api" --format="value(config.name)" | grep -q .; then
    echo "  already enabled  $api"
  else
    echo "  enabling         $api"
    gcloud services enable "$api" --project "$PROJECT" >/dev/null
    echo "  waiting 60s for the service agent, because the next command needs it"
    sleep 60
  fi
done

# ------------------------------------------------------------------------ iam
# Both of these are the grants Lab 6 tells students to make by hand, and both
# fail late rather than early when they are missing. Making them here means the
# hour does not discover them at pipeline run.
say "The two grants that fail late when they are missing"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
if gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
      --format="value(bindings.role)" --filter="bindings.members:$COMPUTE_SA" \
      | grep -qx "roles/editor"; then
  echo "  already held     $COMPUTE_SA  roles/editor"
else
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member "serviceAccount:$COMPUTE_SA" --role roles/editor >/dev/null
  echo "  granted          $COMPUTE_SA  roles/editor"
fi

# ------------------------------------------------------------------- instance
say "Cloud Data Fusion instance, Basic edition. This is the wait."
T0=$(date +%s)
gcloud beta data-fusion instances create "$INSTANCE" --project "$PROJECT" \
  --location "$REGION" --edition basic --async \
  --labels=course=dsba6190,environment=demo,session=06 >/dev/null

# The create can abort inside three seconds with "Failed to perform tenant
# project creation", which is not a permissions problem and not a quota
# problem. Re-issuing the same command is the fix. It happened twice on
# 10 September and the third attempt built normally.
ATTEMPT=1
while true; do
  STATE="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
             --location "$REGION" --format='value(state)' 2>/dev/null || true)"
  case "$STATE" in
    RUNNING) break ;;
    FAILED)
      echo "  instance reported FAILED; deleting and re-issuing"
      gcloud beta data-fusion instances delete "$INSTANCE" --project "$PROJECT" \
        --location "$REGION" --quiet >/dev/null 2>&1 || true
      STATE="" ;;
  esac
  if [ -z "$STATE" ]; then
    LASTERR="$(gcloud beta data-fusion instances list --project "$PROJECT" \
                 --location "$REGION" --format="value(name)" 2>/dev/null | grep -c "$INSTANCE" || true)"
    if [ "$LASTERR" = "0" ] && [ "$ATTEMPT" -lt 5 ]; then
      ATTEMPT=$(( ATTEMPT + 1 ))
      echo "  create aborted; attempt $ATTEMPT"
      gcloud beta data-fusion instances create "$INSTANCE" --project "$PROJECT" \
        --location "$REGION" --edition basic --async >/dev/null 2>&1 || true
    fi
  fi
  printf '  %4ss  %s\n' "$(( $(date +%s) - T0 ))" "${STATE:-CREATING}"
  sleep 30
done
ELAPSED=$(( $(date +%s) - T0 ))
echo "  RUNNING after $(( ELAPSED / 60 )) min $(( ELAPSED % 60 )) s, on attempt $ATTEMPT"

ENDPOINT="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
              --location "$REGION" --format='value(apiEndpoint)')"
CONSOLE="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
             --location "$REGION" --format='value(serviceEndpoint)')"
SPARK_SA="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
              --location "$REGION" --format='value(dataprocServiceAccount)')"
# `dataprocServiceAccount` is empty on a default instance, which means the
# ephemeral Dataproc cluster runs as the default compute service account. That
# is the account the lab's second grant is about, whatever the Instance details
# page calls it.
[ -z "$SPARK_SA" ] && SPARK_SA="$COMPUTE_SA"

# Grant two, which the lab names: the cluster's identity needs the Cloud Data
# Fusion API Service Agent role. Without it the run fails at PROVISION with a
# list of missing storage permissions, roughly five seconds in, and Editor on
# the same account does not substitute for it.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:$SPARK_SA" \
  --role roles/datafusion.serviceAgent --condition=None >/dev/null
echo "  granted          $SPARK_SA  roles/datafusion.serviceAgent"

# Grant three, which the lab does not name and which the rehearsal on
# 10 September found the hard way: the Data Fusion service agent has to be
# allowed to act as the cluster's identity. Without it the run fails at
# PROVISION with "User not authorized to act as service account", about five
# seconds in, after the first two grants are already correct.
FUSION_SA="service-$PROJECT_NUMBER@gcp-sa-datafusion.iam.gserviceaccount.com"
gcloud iam service-accounts add-iam-policy-binding "$SPARK_SA" --project "$PROJECT" \
  --member "serviceAccount:$FUSION_SA" \
  --role roles/iam.serviceAccountUser >/dev/null
echo "  granted          $FUSION_SA  roles/iam.serviceAccountUser on $SPARK_SA"

echo "  IAM propagates for up to a minute. The instance build covers it."

# --------------------------------------------------------------- the estate
say "Bucket, dataset, and the two extracts"
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" \
       --uniform-bucket-level-access >/dev/null
bq --project_id="$PROJECT" mk --location="$REGION" -d "$DATASET" >/dev/null

rm -rf "$WORK"; mkdir -p "$WORK"
python3 "$HERE/sample/make-sample.py" "$WORK/sample" >/dev/null
gcloud storage cp "$WORK/sample/pos-2026-09-24.csv" "gs://$BUCKET/raw/pos/" >/dev/null

say "Pipeline definitions, pinned to the artifact versions this instance carries"
GCPV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="google-cloud"{print $2}' | head -1)"
WRGV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="wrangler-transform"{print $2}' | head -1)"
CORV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="core-plugins"{print $2}' | head -1)"
PIPV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="cdap-data-pipeline"{print $2}' | head -1)"
python3 "$HERE/pipelines/make-pipelines.py" "$WORK/pipelines" "$PROJECT" "$BUCKET" "$DATASET" \
  --gcp-version "$GCPV" --wrangler-version "$WRGV" --core-version "$CORV" \
  --pipeline-version "$PIPV"

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export REGION="$REGION"
export INSTANCE="$INSTANCE"
export BUCKET="$BUCKET"
export DATASET="$DATASET"
export TABLE="$TABLE"
export FQ="$PROJECT.$DATASET.$TABLE"
export ENDPOINT="$ENDPOINT"
export CONSOLE="$CONSOLE"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
ENVEOF

cat <<DONE

  Staged for the live demo. The instance is running and nothing is deployed.

  Working directory   $WORK
  Project             $PROJECT
  Region              $REGION
  Name suffix         $SUFFIX
  Instance built in   $(( ELAPSED / 60 )) min $(( ELAPSED % 60 )) s, on attempt $ATTEMPT

  Load the names into the shell you will teach from:

      source $WORK/env.sh

  Running, and metered from now until you delete it:
    $INSTANCE          Basic edition, \$1.80 per instance-hour

  Open the Studio at:
    $CONSOLE

  Created, empty, and waiting for the hour:
    gs://$BUCKET/raw/pos/pos-2026-09-24.csv
    $DATASET   (no tables; step 4 creates the first one)

  NOT created. The hour deploys each of these at its own step:
    pos-01-baseline    step 3   GCS, Wrangler, BigQuery
    pos-02-quarantine  step 7   the same, plus the error port and an error sink
    pos-03-idempotent  step 9   the same, with a sink that replaces
    pos-04-drift       step 10  the same, with one directive missing

  Pipeline JSON, ready to import if the Studio has moved:
    $WORK/pipelines/

  Held back for step 6, because the malformed day arrives mid-hour:
    $WORK/sample/pos-2026-09-24-dirty.csv

  Upload it at step 6 with:

      gcloud storage cp $WORK/sample/pos-2026-09-24-dirty.csv \\
        gs://$BUCKET/raw/pos/pos-2026-09-24.csv

  Verify now, while there is time to fix it:

      python3 $HERE/cdap.py artifacts --endpoint \$ENDPOINT

  Expect four rows: cdap-data-pipeline, core-plugins, google-cloud,
  wrangler-transform. An empty answer means the instance is running but its
  API is not serving yet. Wait two minutes and try again.

  TEAR DOWN THE SAME EVENING. The instance bills \$1.80 per instance-hour,
  which is \$25.20 for one night and \$1,296 for a month:

      gcloud beta data-fusion instances delete $INSTANCE \\
        --project $PROJECT --location $REGION --quiet
      bq --project_id=$PROJECT rm -r -f -d $DATASET
      gcloud storage rm --recursive gs://$BUCKET --project $PROJECT

  Then the three buckets nobody asked for. Two are Dataproc's, written on the
  first run that built a cluster, and one is the instance's own:

      gcloud storage ls --project $PROJECT | grep -E 'dataproc-(staging|temp)-'
      gcloud storage buckets list --project $PROJECT \\
        --filter='labels.cdf_instance=$INSTANCE' --format='value(name)'

  Delete what those two commands list.

  Step 12 performs the first line in front of the room. Confirm all of it with:

      gcloud beta data-fusion instances list --project $PROJECT --location $REGION
      gcloud dataproc clusters list --project $PROJECT --region $REGION
      bq --project_id=$PROJECT ls
      gcloud storage ls --project $PROJECT

DONE
