#!/usr/bin/env bash
# Capture the Session 10 demo: read a plan, find the skew.
#
#   ./capture.sh <PROJECT_ID>
#
# Runs Queen City Trip Analytics' nightly corporate-billing job five times on
# Serverless for Apache Spark: once to generate 30 million trips, then the
# skewed baseline, a broadcast join, a salted join and adaptive query
# execution. Each run writes a Spark event log to Cloud Storage; stages.py
# turns it into the task-duration summary the Spark UI shows. The same
# aggregation then runs in BigQuery. Everything is deleted through an exit
# trap. Cost: well under a dollar.
#
# DO NOT RUN THIS IN CLASS.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/capture"; mkdir -p "$OUT" "$HERE/plan"
SUFFIX="$(date +%s | tail -c 6)"
REGION=us-central1
BUCKET="qc-billing-$SUFFIX"; BASE="gs://$BUCKET"; DATASET="qc_billing_$SUFFIX"
WORK="$HERE/.work"; rm -rf "$WORK"; mkdir -p "$WORK"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () { local label="$1"; local out="$OUT/$2"; shift 2
          { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"; }
cleanup () {
  step "Cleanup"
  gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT" >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}" >/dev/null 2>&1 || true
  echo "  Cleanup finished."
}
trap cleanup EXIT

gcloud services enable dataproc.googleapis.com --project "$PROJECT" >/dev/null
gcloud storage buckets create "$BASE" --project "$PROJECT" --location "$REGION" --uniform-bucket-level-access >/dev/null
gcloud storage cp "$HERE/jobs/billing.py" "$BASE/jobs/billing.py" >/dev/null

COMMON="spark.eventLog.enabled=true,spark.eventLog.compress=false,spark.eventLog.dir=$BASE/eventlogs,spark.dynamicAllocation.enabled=false,spark.executor.instances=2,spark.executor.cores=4,spark.sql.shuffle.partitions=200"
batch () {  # batch <name> <mode> <extra properties>
  local id="qc-$1-$SUFFIX" t0; t0=$(date +%s)
  gcloud dataproc batches submit pyspark "$BASE/jobs/billing.py" --project "$PROJECT" --region "$REGION" \
    --batch "$id" --version 2.2 --properties "$COMMON${3:+,$3}" -- "$2" "$BASE" ${4:-} 2>&1 | grep -E "^(generated|$2:)" || true
  echo "wall clock $(( $(date +%s) - t0 )) s"
  echo "$id" > "$WORK/$1.id"
}
evlog () {  # evlog <name>: download the newest event log written after the batch started
  local f; f=$(gcloud storage ls "$BASE/eventlogs/" | sort | tail -1)
  gcloud storage cp "$f" "$WORK/$1.events" >/dev/null && python3 "$HERE/stages.py" "$WORK/$1.events"
}

step "Step 1 · Generate a year of trips"
run "gcloud dataproc batches submit pyspark billing.py -- generate \$BASE 30000000" 01-generate.txt batch gen generate "" 30000000
run "gcloud storage du -s \$BASE/data/trips \$BASE/data/accounts" 02-data-size.txt \
    bash -c "gcloud storage du -s $BASE/data/trips $BASE/data/accounts"

step "Steps 2 and 3 · The skewed baseline and its plan"
OFF="spark.sql.adaptive.enabled=false,spark.sql.autoBroadcastJoinThreshold=-1"
run "batch baseline   (AQE off, broadcast off)" 03-baseline.txt batch baseline baseline "$OFF"
gcloud storage cat "$BASE/plans/baseline/part-*" > "$HERE/plan/skewed-plan.txt"
run "head -22 plan/skewed-plan.txt" 04-plan-tree.txt head -22 "$HERE/plan/skewed-plan.txt"
run "python3 stages.py <baseline event log>" 05-baseline-stages.txt evlog baseline

step "Step 5 · The cause, in the data"
bq --project_id="$PROJECT" --location=US mk --dataset "$PROJECT:$DATASET" >/dev/null
bq --project_id="$PROJECT" --location=US load --source_format=PARQUET "$PROJECT:$DATASET.trips" "$BASE/data/trips/*.parquet" >/dev/null
bq --project_id="$PROJECT" --location=US load --source_format=PARQUET "$PROJECT:$DATASET.accounts" "$BASE/data/accounts/*.parquet" >/dev/null
run "bq query \"SELECT account_id, COUNT(*) trips, share FROM trips GROUP BY 1 ORDER BY 2 DESC LIMIT 5\"" 06-key-counts.txt \
    bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
    "SELECT account_id, COUNT(*) AS trips, ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share
     FROM \`$PROJECT.$DATASET.trips\` GROUP BY 1 ORDER BY 2 DESC LIMIT 5"

step "Step 6 · Broadcast"
run "batch broadcast   (broadcast hint on accounts)" 07-broadcast.txt batch broadcast broadcast "$OFF"
gcloud storage cat "$BASE/plans/broadcast/part-*" > "$HERE/plan/broadcast-plan.txt"
run "python3 stages.py <broadcast event log>" 08-broadcast-stages.txt evlog broadcast

step "Step 7 · Salted"
run "batch salted   (32 salts on the join key)" 09-salted.txt batch salted salted "$OFF"
gcloud storage cat "$BASE/plans/salted/part-*" > "$HERE/plan/salted-plan.txt"
run "python3 stages.py <salted event log>" 10-salted-stages.txt evlog salted

step "Step 8 · Adaptive query execution"
run "batch aqe   (AQE and skew join on, broadcast off)" 11-aqe.txt batch aqe aqe \
    "spark.sql.adaptive.enabled=true,spark.sql.adaptive.skewJoin.enabled=true,spark.sql.autoBroadcastJoinThreshold=-1"
gcloud storage cat "$BASE/plans/aqe/part-*" > "$HERE/plan/aqe-plan.txt"
run "python3 stages.py <aqe event log>" 12-aqe-stages.txt evlog aqe
run "python3 stages.py --largest <baseline, salted, aqe event logs>" 16-largest-task.txt bash -c \
    "for v in baseline salted aqe; do echo \$v; python3 '$HERE/stages.py' --largest '$WORK'/\$v.events; echo; done"
run "python3 stages.py --final-plan <aqe event log>" 17-aqe-final-plan.txt python3 "$HERE/stages.py" --final-plan "$WORK/aqe.events"
run "python3 stages.py --app-time <each event log>" 18-app-time.txt bash -c \
    "for v in baseline broadcast salted aqe; do printf '%-10s ' \$v; python3 '$HERE/stages.py' --app-time '$WORK'/\$v.events; done"

step "Step 9 · The same answer in BigQuery"
run "bq query <the same join and aggregation>" 13-bigquery.txt \
    bash -c "id=qc_${SUFFIX}_\$RANDOM; bq --project_id=$PROJECT --quiet query --use_legacy_sql=false --nouse_cache --format=pretty --job_id=\$id \
      \"SELECT a.tier, DATE_TRUNC(t.pickup_date, MONTH) AS month, COUNT(*) AS trips, ROUND(SUM(t.fare), 2) AS revenue
        FROM \\\`$PROJECT.$DATASET.trips\\\` t JOIN \\\`$PROJECT.$DATASET.accounts\\\` a USING (account_id)
        GROUP BY 1, 2 ORDER BY 1, 2 LIMIT 6\" && bq --project_id=$PROJECT --format=json show -j \$id \
      | python3 -c 'import json,sys; q=json.load(sys.stdin)[\"statistics\"][\"query\"]; print(\"slot time\", round(int(q[\"totalSlotMs\"])/1000,1), \"s · processed\", round(int(q[\"totalBytesProcessed\"])/2**20,1), \"MB · stages\", len(q[\"queryPlan\"]))'"

step "Answers agree"
run "row counts and total revenue per variant" 14-agree.txt bash -c "
for v in baseline broadcast salted aqe; do
  bq --project_id=$PROJECT --location=US load --replace --source_format=PARQUET $PROJECT:$DATASET.out_\$v '$BASE/out/'\$v'/*.parquet' >/dev/null
  bq --project_id=$PROJECT --quiet query --use_legacy_sql=false --format=csv \"SELECT '\$v', COUNT(*), ROUND(SUM(revenue),2) FROM \\\`$PROJECT.$DATASET.out_\$v\\\`\" | tail -1
done"

step "Teardown"
run "gcloud storage rm -r \$BASE; bq rm -r -f -d \$DATASET" 15-teardown.txt bash -c \
    "gcloud storage rm -r gs://${BUCKET:?} --project $PROJECT 2>&1 | tail -1; bq --project_id=$PROJECT rm -r -f -d ${DATASET:?}; gcloud dataproc batches list --project $PROJECT --region $REGION --filter='state=RUNNING' 2>&1 | tail -1"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
for f in "$OUT"/*.txt "$HERE"/plan/*.txt; do sed -i '' -e "s/$NUMBER/PROJECT_NUMBER/g" -e "s#$BASE#gs://qc-billing#g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
