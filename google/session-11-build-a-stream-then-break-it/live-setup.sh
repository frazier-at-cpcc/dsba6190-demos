#!/usr/bin/env bash
# Stage the Session 11 live demo: build a stream, then break it.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Provisions what the hour cannot wait for: the register-events topic with
# three subscriptions, the dead-letter topic and its subscription, a staging
# bucket, a BigQuery dataset, and three Dataflow streaming jobs for Crown
# Street Markets (baseline, allowed lateness, deduplication). It blocks until
# all three jobs report Running and the baseline job has written its first
# rows, using small warm-up bursts that the hour's queries filter out.
#
# Run it at T minus 30. On 27 September 2026 the jobs reached Running 111 s
# after submission and wrote first rows at 250 s.
# Applies. Never destroys. The teardown it prints is step 11.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-11}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
REGION="${REGION:-us-central1}"
TOPIC="register-events-$SUFFIX"; DLQ="register-dlq-$SUFFIX"; SCRATCH="hello-$SUFFIX"
BUCKET="crown-stream-$SUFFIX"; DATASET="crown_stream_$SUFFIX"
T="projects/$PROJECT/topics"; S="projects/$PROJECT/subscriptions"
PY="uv run --quiet --python 3.11 --with apache-beam[gcp]==2.76.0 python"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "APIs, and the Dataflow service agent"
gcloud services enable dataflow.googleapis.com pubsub.googleapis.com --project "$PROJECT" >/dev/null
# A freshly enabled Dataflow API can launch jobs before its service agent holds
# its role; on 27 September 2026 all three jobs failed that way. Grant it.
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
gcloud beta services identity create --service dataflow.googleapis.com --project "$PROJECT" >/dev/null 2>&1 || true
gcloud projects add-iam-policy-binding "$PROJECT" --condition=None \
  --member "serviceAccount:service-$NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com" \
  --role roles/dataflow.serviceAgent >/dev/null
# Workers run without external IPs, so the subnet must reach Google APIs privately.
PGA="$(gcloud compute networks subnets describe default --region "$REGION" --project "$PROJECT" \
         --format='value(privateIpGoogleAccess)' 2>/dev/null || true)"
[ "$PGA" = "True" ] || echo "  WARNING: Private Google Access is not on for the default subnet in $REGION."
sleep 60

step "Topics, subscriptions, bucket, dataset"
rm -rf "$WORK"; mkdir -p "$WORK"
gcloud pubsub topics create "$TOPIC" "$DLQ" --project "$PROJECT" >/dev/null
for s in baseline lateness dedup; do gcloud pubsub subscriptions create "$s-$SUFFIX" --topic "$TOPIC" --project "$PROJECT" >/dev/null; done
gcloud pubsub subscriptions create "dlq-$SUFFIX" --topic "$DLQ" --project "$PROJECT" >/dev/null
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" --uniform-bucket-level-access >/dev/null
bq --project_id="$PROJECT" --location=US mk --dataset "$PROJECT:$DATASET" >/dev/null

step "Launch three streaming jobs"
cp -R "$HERE/pipeline" "$WORK/pipeline"; rm -rf "$WORK/pipeline/__pycache__"
for v in baseline lateness dedup; do
  (cd "$WORK/pipeline" && $PY register_stream.py --variant "$v" --subscription "$S/$v-$SUFFIX" \
     --dlq_topic "$T/$DLQ" --table "$PROJECT:$DATASET.sales_$v" \
     --runner DataflowRunner --project "$PROJECT" --region "$REGION" --job_name "crown-$v-$SUFFIX" \
     --temp_location "gs://$BUCKET/tmp" --staging_location "gs://$BUCKET/staging" \
     --max_num_workers 1 --worker_machine_type e2-standard-2 --enable_streaming_engine --no_use_public_ips 2>&1 | grep submitted) &
done
wait
J0=$(date +%s)

step "Wait for Running"
until [ "$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active \
            --filter="name~crown-.*-$SUFFIX AND state=Running" --format='value(id)' | wc -l | tr -d ' ')" = "3" ]; do
  sleep 15
done
echo "  jobs running $(( $(date +%s) - J0 )) s after submission"

step "Warm up until the baseline table exists"
# Workers start after the job reports Running. These five-sale bursts land in
# windows before the hour's burst, so every query in the hour filters them out.
until bq --project_id="$PROJECT" show "$PROJECT:$DATASET.sales_baseline" >/dev/null 2>&1; do
  (cd "$WORK/pipeline" && $PY registers.py "$T/$TOPIC" burst 5 >/dev/null); sleep 30
done
echo "  first rows $(( $(date +%s) - J0 )) s after submission"

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export REGION="$REGION"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export TOPIC="$TOPIC"
export DLQ="$DLQ"
export SCRATCH="$SCRATCH"
export BUCKET="$BUCKET"
export DATASET="$DATASET"
export T="$T"
export S="$S"
export PY="$PY"
q () { bq --project_id="\$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty "\$1"; }
cd "$WORK"
ENVEOF
READY=$(( $(date +%s) - T0 ))

cat <<DONE

  Staged for the live demo in $(( READY / 60 )) min $(( READY % 60 )) s. Three jobs are running.

  Working directory   $WORK
  Name suffix         $SUFFIX
  Topic               $TOPIC   (subscriptions baseline-, lateness-, dedup-$SUFFIX)
  Dead-letter topic   $DLQ   (subscription dlq-$SUFFIX)
  Jobs                crown-baseline-$SUFFIX, crown-lateness-$SUFFIX, crown-dedup-$SUFFIX
                      ($REGION, one e2-standard-2 worker each, Streaming Engine, no external IPs)
  Dataset             $PROJECT:$DATASET

  Load the names into the shell you will teach from:

      source $WORK/env.sh

  NOT created. The hour creates it at step 1:
    Topic and subscription $SCRATCH

  The jobs bill every minute they run. Teardown is step 11, and it is also:
    gcloud dataflow jobs list --project $PROJECT --region $REGION --status=active --filter="name~crown-.*-$SUFFIX"
    gcloud dataflow jobs cancel <each id> --project $PROJECT --region $REGION
    for s in baseline lateness dedup dlq; do gcloud pubsub subscriptions delete \$s-$SUFFIX --project $PROJECT --quiet; done
    gcloud pubsub subscriptions delete $SCRATCH --project $PROJECT --quiet
    gcloud pubsub topics delete $TOPIC $DLQ $SCRATCH --project $PROJECT --quiet
    bq --project_id=$PROJECT rm -r -f -d $DATASET
    gcloud storage rm -r gs://$BUCKET --project $PROJECT
DONE
