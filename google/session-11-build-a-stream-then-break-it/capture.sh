#!/usr/bin/env bash
# Capture the Session 11 demo: build a stream, then break it.
#
#   ./capture.sh <PROJECT_ID>
#
# Creates a register-events topic with three subscriptions and a dead-letter
# topic, launches three Dataflow streaming jobs (baseline, allowed lateness,
# deduplication), publishes Crown Street Markets register sales including a
# late sale, a retried duplicate and a malformed record, records what each job
# wrote to BigQuery, drains one job and cancels another, and tears everything
# down through an exit trap. Cost: under a dollar for about forty minutes.
#
# DO NOT RUN THIS IN CLASS.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/capture"; mkdir -p "$OUT"
SUFFIX="$(date +%s | tail -c 6)"
REGION=us-central1
TOPIC="register-events-$SUFFIX"; DLQ="register-dlq-$SUFFIX"; SCRATCH="hello-$SUFFIX"
BUCKET="crown-stream-$SUFFIX"; DATASET="crown_stream_$SUFFIX"
T="projects/$PROJECT/topics"; S="projects/$PROJECT/subscriptions"
PY="uv run --quiet --python 3.11 --with apache-beam[gcp]==2.76.0 python"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () { local label="$1"; local out="$OUT/$2"; shift 2
          { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"; }
q () { bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty "$1"; }
cleanup () {
  step "Cleanup"
  for j in $(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active \
               --filter="name~crown-.*-$SUFFIX" --format="value(id)" 2>/dev/null); do
    gcloud dataflow jobs cancel "$j" --project "$PROJECT" --region "$REGION" >/dev/null 2>&1 || true
  done
  for s in baseline lateness dedup dlq; do gcloud pubsub subscriptions delete "$s-$SUFFIX" --project "$PROJECT" --quiet >/dev/null 2>&1 || true; done
  gcloud pubsub subscriptions delete "$SCRATCH" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  for t in "$TOPIC" "$DLQ" "$SCRATCH"; do gcloud pubsub topics delete "${t:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true; done
  bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}" >/dev/null 2>&1 || true
  gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT" >/dev/null 2>&1 || true
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Setup"
gcloud services enable dataflow.googleapis.com pubsub.googleapis.com --project "$PROJECT" >/dev/null
# A freshly enabled Dataflow API can launch jobs before its service agent holds
# its role; on 27 September 2026 all three jobs failed that way. Grant it.
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
gcloud beta services identity create --service dataflow.googleapis.com --project "$PROJECT" >/dev/null 2>&1 || true
gcloud projects add-iam-policy-binding "$PROJECT" --condition=None \
  --member "serviceAccount:service-$NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com" \
  --role roles/dataflow.serviceAgent >/dev/null
sleep 60
gcloud pubsub topics create "$TOPIC" "$DLQ" --project "$PROJECT" >/dev/null
for s in baseline lateness dedup; do gcloud pubsub subscriptions create "$s-$SUFFIX" --topic "$TOPIC" --project "$PROJECT" >/dev/null; done
gcloud pubsub subscriptions create "dlq-$SUFFIX" --topic "$DLQ" --project "$PROJECT" >/dev/null
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" --uniform-bucket-level-access >/dev/null
bq --project_id="$PROJECT" --location=US mk --dataset "$PROJECT:$DATASET" >/dev/null

step "Launch three streaming jobs"
for v in baseline lateness dedup; do
  (cd "$HERE/pipeline" && $PY register_stream.py --variant "$v" --subscription "$S/$v-$SUFFIX" \
     --dlq_topic "$T/$DLQ" --table "$PROJECT:$DATASET.sales_$v" \
     --runner DataflowRunner --project "$PROJECT" --region "$REGION" --job_name "crown-$v-$SUFFIX" \
     --temp_location "gs://$BUCKET/tmp" --staging_location "gs://$BUCKET/staging" \
     --max_num_workers 1 --worker_machine_type e2-standard-2 --enable_streaming_engine --no_use_public_ips 2>&1 | grep submitted) &
done
wait
T0=$(date +%s)

step "Step 1 · The substrate, in ninety seconds"
gcloud pubsub topics create "$SCRATCH" --project "$PROJECT" >/dev/null
gcloud pubsub subscriptions create "$SCRATCH" --topic "$SCRATCH" --project "$PROJECT" >/dev/null
run "gcloud pubsub topics publish hello (three times)" 01-publish.txt bash -c "
for i in 1 2 3; do gcloud pubsub topics publish $SCRATCH --project $PROJECT --message \"register test \$i\" --attribute store_id=CLT-00\$i; done"
run "gcloud pubsub subscriptions pull hello --auto-ack --limit 3" 02-pull.txt \
    gcloud pubsub subscriptions pull "$SCRATCH" --project "$PROJECT" --auto-ack --limit 3 \
      --format="table(message.data.decode(base64),message.attributes.store_id,message.messageId)"

step "Step 2 · Three jobs, started before class"
until [ "$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active --filter="name~crown-.*-$SUFFIX AND state=Running" --format='value(id)' | wc -l | tr -d ' ')" = "3" ]; do sleep 15; done
run "gcloud dataflow jobs list --status=active" 03-jobs.txt \
    gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active --filter="name~crown-.*-$SUFFIX" \
      --format="table(name,state,creationTime)"
echo "jobs running $(( $(date +%s) - T0 )) s after submission" > "$OUT/03b-startup.txt"

step "Step 3 · A burst, and rows in BigQuery"
# Workers start after the job reports Running. Warm up until the baseline table exists.
until bq --project_id="$PROJECT" show "$PROJECT:$DATASET.sales_baseline" >/dev/null 2>&1; do
  (cd "$HERE/pipeline" && $PY registers.py "$T/$TOPIC" burst 5 >/dev/null); sleep 30; done
echo "first rows $(( $(date +%s) - T0 )) s after submission" >> "$OUT/03b-startup.txt"
sleep 60
BURST_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run "python registers.py \$TOPIC burst 200" 04-burst.txt bash -c "cd '$HERE/pipeline' && $PY registers.py $T/$TOPIC burst 200"
sleep 150
run "bq query: sales in windows since the burst, per job" 05-burst-rows.txt \
    q "SELECT 'baseline' job, SUM(sales) sales, ROUND(SUM(revenue),2) revenue, COUNT(DISTINCT window_start) windows FROM \`$PROJECT.$DATASET.sales_baseline\` WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)
       UNION ALL SELECT 'dedup', SUM(sales), ROUND(SUM(revenue),2), COUNT(DISTINCT window_start) FROM \`$PROJECT.$DATASET.sales_dedup\` WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)"
run "bq query: the busiest five stores in the burst window" 06-by-store.txt \
    q "SELECT window_start, store_id, sales, revenue, pane FROM \`$PROJECT.$DATASET.sales_baseline\`
       WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE) ORDER BY sales DESC, store_id LIMIT 5"

step "Step 5 · A sale from 30 minutes ago"
run "python registers.py \$TOPIC late   (CLT-031, Ballantyne, offline register)" 07-late.txt \
    bash -c "cd '$HERE/pipeline' && $PY registers.py $T/$TOPIC late"
LATE_WIN=$(date -u -v-30M +%Y-%m-%dT%H:%M:00Z)
sleep 150
run "bq query: CLT-031 in the window it was rung, baseline job" 08-late-baseline.txt \
    q "SELECT window_start, store_id, sales, revenue, pane FROM \`$PROJECT.$DATASET.sales_baseline\`
       WHERE store_id = 'CLT-031' AND window_start < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 20 MINUTE) ORDER BY window_start"
run "bq query: CLT-031 in the window it was rung, allowed-lateness job" 09-late-lateness.txt \
    q "SELECT window_start, store_id, sales, revenue, pane FROM \`$PROJECT.$DATASET.sales_lateness\`
       WHERE store_id = 'CLT-031' AND window_start < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 20 MINUTE) ORDER BY window_start"

step "Step 7 · One sale, published twice"
DUP_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run "python registers.py \$TOPIC duplicate   (a register retry)" 10-duplicate.txt \
    bash -c "cd '$HERE/pipeline' && $PY registers.py $T/$TOPIC duplicate"
sleep 150
run "bq query: CLT-007 since the retry, baseline against dedup" 11-dup-rows.txt \
    q "SELECT 'baseline' job, SUM(sales) sales, ROUND(SUM(revenue),2) revenue FROM \`$PROJECT.$DATASET.sales_baseline\` WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)
       UNION ALL SELECT 'dedup', SUM(sales), ROUND(SUM(revenue),2) FROM \`$PROJECT.$DATASET.sales_dedup\` WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)"

step "Step 8 · A malformed record"
run "python registers.py \$TOPIC malformed   (total sent as \"\$3.49\")" 12-malformed.txt \
    bash -c "cd '$HERE/pipeline' && $PY registers.py $T/$TOPIC malformed"
sleep 90
run "gcloud pubsub subscriptions pull dlq --auto-ack" 13-dlq.txt \
    gcloud pubsub subscriptions pull "dlq-$SUFFIX" --project "$PROJECT" --auto-ack --limit 5 \
      --format="yaml(message.data.decode(base64),message.attributes.error,message.attributes.sale_id)"
run "gcloud dataflow jobs list   (all three still running)" 14-still-running.txt \
    gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active --filter="name~crown-.*-$SUFFIX" \
      --format="table(name,state)"

step "Step 10 · Drain one, cancel another"
BID=$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active --filter="name=crown-baseline-$SUFFIX" --format="value(id)")
LID=$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active --filter="name=crown-lateness-$SUFFIX" --format="value(id)")
run "gcloud dataflow jobs drain crown-baseline; gcloud dataflow jobs cancel crown-lateness" 15-drain-cancel.txt bash -c "
gcloud dataflow jobs drain $BID --project $PROJECT --region $REGION; gcloud dataflow jobs cancel $LID --project $PROJECT --region $REGION"
sleep 240
run "gcloud dataflow jobs list --filter crown   (final states)" 16-final-states.txt \
    gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --filter="name~crown-.*-$SUFFIX" \
      --format="table(name,state)"

step "Step 11 · Teardown"
run "cancel the last job; delete subscriptions, topics, dataset, bucket" 17-teardown.txt bash -c "
for j in \$(gcloud dataflow jobs list --project $PROJECT --region $REGION --status=active --filter='name~crown-.*-$SUFFIX' --format='value(id)'); do gcloud dataflow jobs cancel \$j --project $PROJECT --region $REGION; done
for s in baseline lateness dedup dlq; do gcloud pubsub subscriptions delete \$s-$SUFFIX --project $PROJECT --quiet 2>&1 | tail -1; done
gcloud pubsub subscriptions delete $SCRATCH --project $PROJECT --quiet 2>&1 | tail -1
gcloud pubsub topics delete ${TOPIC:?} ${DLQ:?} ${SCRATCH:?} --project $PROJECT --quiet 2>&1 | tail -3
bq --project_id=$PROJECT rm -r -f -d ${DATASET:?}
gcloud storage rm -r gs://${BUCKET:?} --project $PROJECT 2>&1 | tail -1"
sleep 60
run "verify: active jobs, topics" 18-verify.txt bash -c "
gcloud dataflow jobs list --project $PROJECT --region $REGION --status=active --filter='name~crown-.*-$SUFFIX'; gcloud pubsub topics list --project $PROJECT --filter='name~$SUFFIX'"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
for f in "$OUT"/*.txt; do sed -i '' -e "s/$NUMBER/PROJECT_NUMBER/g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
