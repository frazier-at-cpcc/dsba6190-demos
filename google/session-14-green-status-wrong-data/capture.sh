#!/usr/bin/env bash
# Capture the Session 14 live demo: green status, wrong data.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh into .work/, runs all eight steps against real
# BigQuery, Cloud Storage, Cloud Logging and Cloud Monitoring, writes every
# command's output to capture/, and removes everything this run created through
# an exit trap: the alerting policy first, because a log-based metric cannot be
# deleted while a policy uses it, then the channel, the metric, the log, the
# bucket and both datasets.
#
# Cost of one run: under one cent. Load jobs are free, the table is about
# 70 MB, and log-based metrics and alerting policies at this volume are free.
#
# It stages, runs and deletes everything in one pass. To follow the steps
# yourself, prefer prep.ipynb and demo.ipynb.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"
OUT="$HERE/capture"
export SUFFIX="$(date +%s | tail -c 6)"
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}

cleanup () {
  step "Cleanup"
  local pol ch
  # Find this run's policy and channel by the run number in their display names.
  pol="$(gcloud monitoring policies list --project "$PROJECT" --format='value(name,displayName)' 2>/dev/null \
           | grep "(run ${SUFFIX:?})" | cut -f1 || true)"
  for p in $pol; do gcloud monitoring policies delete "${p:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true; done
  ch="$(gcloud beta monitoring channels list --project "$PROJECT" --format='value(name,displayName)' 2>/dev/null \
          | grep "(run ${SUFFIX:?})" | cut -f1 || true)"
  for c in $ch; do gcloud beta monitoring channels delete "${c:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true; done
  gcloud logging metrics delete "s14_dq_red_${SUFFIX:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud logging logs delete "s14-dq-${SUFFIX:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud storage rm -r "gs://s14-store-sales-raw-${SUFFIX:?}" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" rm -r -f -d "store_ops_${SUFFIX:?}" >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" rm -r -f -d "store_ops_bak_${SUFFIX:?}" >/dev/null 2>&1 || true
  echo "  Cleanup finished for run $SUFFIX."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"
T="\`$DS.store_sales\`"
GOOD="gs://$BUCKET/raw/dt=$LAST_NIGHT/sales.csv"
OLD="gs://$BUCKET/raw/dt=$FIRST_NIGHT/sales.csv"
DASH="SELECT COUNT(*) AS store_days, ROUND(SUM(sales)) AS sales_usd FROM (
       SELECT sale_date, store_id, region, COUNT(DISTINCT basket_id) AS baskets,
              SUM(items) AS items, SUM(basket_value) AS sales
       FROM $T
       WHERE @@FILTER@@
       GROUP BY 1, 2, 3)"

# Multi-command steps, run in this shell so lib.sh's functions are in scope.
fix_schema () { nightly_load "$GOOD" && PIPELINE=fix q "ALTER TABLE $T DROP COLUMN basket_total"; }
reload_green () { nightly_load "$GOOD" && echo && checks; }
break_and_log () { nightly_load "gs://$BUCKET/incoming/one-store.csv" >/dev/null && log_checks; }
error_budget () { PIPELINE=slo_report q "$(sed "s/@@DS@@/$DS/g" sql/error-budget.sql)"; }
mistake () {
  echo "recovery point $BEFORE"
  PIPELINE=mistake q "DELETE FROM $T
   WHERE sale_date = '$LAST_NIGHT'
   -- AND register_id = 'CLT-040-R99'   the line that was meant to be here"
}
restore () {
  PIPELINE=restore q "CREATE TEMP TABLE lost AS
   SELECT * FROM $T FOR SYSTEM_TIME AS OF TIMESTAMP '$BEFORE' WHERE sale_date = '$LAST_NIGHT';
   INSERT INTO $T SELECT * FROM lost;"
}
snapshot () {
  bq --project_id="$PROJECT" --location=US mk --dataset --label team:replenishment "$PROJECT:$BACKUP"
  PIPELINE=backup q "CREATE SNAPSHOT TABLE \`$PROJECT.$BACKUP.store_sales_$LAST_ID\`
   CLONE $T
   OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))"
  bq --project_id="$PROJECT" ls "$PROJECT:$BACKUP"
}
dash_as_written () { PIPELINE=replenishment_dashboard q "${DASH/@@FILTER@@/DATE_DIFF(CURRENT_DATE('America/New_York'), sale_date, DAY) BETWEEN 1 AND 7}"; }
dash_pruned () { PIPELINE=replenishment_dashboard q "${DASH/@@FILTER@@/sale_date BETWEEN DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 7 DAY)
                         AND DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY)}"; }

# ------------------------------------------------------------------ step 1
step "Step 1 · The nightly load succeeds"
run "bq show store_sales   (partitioning, labels, rows before last night)" 01-table.txt \
    bash -c "bq --project_id=$PROJECT --format=json show $PROJECT:$DATASET.store_sales \
             | jq '{labels, timePartitioning, numRows}'"
run "nightly_load gs://\$BUCKET/raw/dt=\$LAST_NIGHT/sales.csv" 02-load-good.txt nightly_load "$GOOD"
run "q \"SELECT sale_date, COUNT(*) FROM store_sales WHERE sale_date >= last night - 3 GROUP BY 1\"" 03-recent-nights.txt \
    q "SELECT sale_date, COUNT(*) AS \`rows\`, ROUND(SUM(basket_value)) AS sales_usd FROM $T
       WHERE sale_date >= DATE_SUB('$LAST_NIGHT', INTERVAL 3 DAY) GROUP BY 1 ORDER BY 1"

# ------------------------------------------------------------------ step 2
step "Step 2 · Four checks in SQL"
run "checks   (sql/checks.sql: freshness, volume, schema, distribution)" 04-checks-green.txt checks

# ------------------------------------------------------------------ step 3
step "Step 3 · Break it three ways"
run "nightly_load gs://\$BUCKET/incoming/one-store.csv" 05-load-one-store.txt nightly_load "gs://$BUCKET/incoming/one-store.csv"
run "checks" 06-checks-volume.txt checks
run "nightly_load gs://\$BUCKET/incoming/renamed-column.csv" 07-load-renamed.txt nightly_load "gs://$BUCKET/incoming/renamed-column.csv"
run "checks" 08-checks-schema.txt checks
run "nightly_load \$GOOD; ALTER TABLE store_sales DROP COLUMN basket_total" 09-fix-schema.txt fix_schema
run "nightly_load gs://\$BUCKET/incoming/north-nulls.csv" 10-load-north.txt nightly_load "gs://$BUCKET/incoming/north-nulls.csv"
run "checks" 11-checks-distribution.txt checks
run "q \"SELECT region, COUNT(*), COUNTIF(basket_value IS NULL), AVG(basket_value) ... last night\"" 12-north-by-region.txt \
    q "SELECT region, COUNT(*) AS \`rows\`, COUNTIF(basket_value IS NULL) AS null_values,
              ROUND(AVG(basket_value), 2) AS mean_basket
       FROM $T WHERE sale_date = '$LAST_NIGHT' GROUP BY 1 ORDER BY 1"
run "nightly_load \$GOOD; checks" 13-reload-green.txt reload_green

# ------------------------------------------------------------------ step 4
step "Step 4 · Make one check a symptom alert"
run "log_checks   (one structured entry per check, with gcloud logging write)" 14-log-checks.txt log_checks
run "cat metric.yaml && gcloud logging metrics create \$METRIC --config-from-file=metric.yaml" 15-metric.txt \
    bash -c "cat metric.yaml; echo; gcloud logging metrics create $METRIC --config-from-file=metric.yaml --project $PROJECT"
run "gcloud beta monitoring channels create --type=email --channel-labels=email_address=instructor@example.edu" 16-channel.txt \
    bash -c "gcloud beta monitoring channels create --project $PROJECT --display-name='Replenishment on-call (run $SUFFIX)' \
               --type=email --channel-labels=email_address=instructor@example.edu \
               --format='value(name)' > channel.name && cat channel.name"
CHANNEL="$(cat "$WORKDIR/channel.name")"
create_policy () {  # a new log-based metric can take minutes to become visible to Monitoring
  local n=0
  until gcloud monitoring policies create --project "$PROJECT" --policy-from-file=policy.json \
          --notification-channels="$CHANNEL" --format='value(name)' > policy.name 2>/dev/null; do
    n=$((n + 1)); [ "$n" -ge 20 ] && return 1
    echo 'The new metric is not visible to Monitoring yet. Retrying in 30 s.'; sleep 30
  done
  cat policy.name
}
run "gcloud monitoring policies create --policy-from-file=policy.json --notification-channels=\$CHANNEL" 17-policy.txt create_policy
POLICY="$(cat "$WORKDIR/policy.name")"
run "gcloud monitoring policies describe \$POLICY" 18-policy-describe.txt \
    gcloud monitoring policies describe "$POLICY" --project "$PROJECT" \
      --format="yaml(displayName,enabled,conditions[0].conditionThreshold.filter,conditions[0].conditionThreshold.comparison,conditions[0].conditionThreshold.thresholdValue,notificationChannels.len())"
run "nightly_load one-store.csv; log_checks   (last night breaks again)" 19-break-and-log.txt break_and_log
sleep 20
run "gcloud logging read 'logName=projects/\$PROJECT/logs/\$LOG AND jsonPayload.status=RED' --limit=1" 20-log-read.txt \
    bash -c "gcloud logging read 'logName=\"projects/$PROJECT/logs/$LOG\" AND jsonPayload.status=\"RED\"' \
               --project $PROJECT --limit=1 --format=json | jq '.[0] | {severity, logName, jsonPayload}'"
nightly_load "$GOOD" >/dev/null

# ------------------------------------------------------------------ step 5
step "Step 5 · The SLO and the error budget"
run "q \"the three nights that were not clean, from load_runs\"" 21-bad-nights.txt \
    q "SELECT sale_date, state, finished_at, rows_loaded, corrected_at FROM \`$DS.load_runs\`
       WHERE TIME(finished_at) > '06:00:00' OR corrected_at IS NOT NULL ORDER BY 1"
run "PIPELINE=slo_report q \"\$(cat sql/error-budget.sql)\"" 22-error-budget.txt error_budget
sleep 90
run "red_count   (the log-based metric, read back from Cloud Monitoring)" 23-red-count.txt red_count

# ------------------------------------------------------------------ step 6
step "Step 6 · Delete by mistake, restore with time travel"
BEFORE="$(date -u +%FT%TZ)"; sleep 2
run "BEFORE=\$(date -u +%FT%TZ); PIPELINE=mistake q \"DELETE FROM store_sales WHERE sale_date = last night\"" 24-mistake.txt mistake
run "checks" 25-checks-after-delete.txt checks
run "PIPELINE=restore q \"CREATE TEMP TABLE lost AS ... FOR SYSTEM_TIME AS OF '\$BEFORE'; INSERT INTO store_sales SELECT * FROM lost\"" 26-restore.txt restore
run "checks" 27-checks-after-restore.txt checks
run "q \"RPO and RTO for this event, from INFORMATION_SCHEMA.JOBS\"" 28-rpo-rto.txt \
    q "WITH ours AS (
         SELECT job_id, l.value AS step, start_time, end_time
         FROM \`region-us\`.INFORMATION_SCHEMA.JOBS AS j, UNNEST(j.labels) AS l
         WHERE l.key = 'pipeline' AND l.value IN ('mistake', 'restore') AND j.parent_job_id IS NULL
           AND EXISTS (SELECT 1 FROM UNNEST(j.labels) AS r WHERE r.key = 'run' AND r.value = '$SUFFIX')
           AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR))
       SELECT o.step, FORMAT_TIMESTAMP('%T', o.end_time) AS finished_utc,
              SUM(IF(j.statement_type = 'DELETE', j.dml_statistics.deleted_row_count, 0)) AS deleted,
              SUM(IF(j.statement_type = 'INSERT', j.dml_statistics.inserted_row_count, 0)) AS inserted,
              TIMESTAMP_DIFF(o.end_time, MIN(o.end_time) OVER (), SECOND) AS s_after_mistake
       FROM ours AS o
       JOIN \`region-us\`.INFORMATION_SCHEMA.JOBS AS j
         ON (j.job_id = o.job_id OR j.parent_job_id = o.job_id)
        AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
       GROUP BY o.step, o.start_time, o.end_time ORDER BY o.end_time"
run "bq mk --dataset \$BACKUP; CREATE SNAPSHOT TABLE \$BACKUP.store_sales_\$LAST_ID CLONE store_sales" 29-snapshot.txt snapshot

# ------------------------------------------------------------------ step 7
step "Step 7 · FinOps: labels, the cheapest fix, and a storage move nobody notices"
run "q \"the replenishment dashboard's query, as written\"" 30-dashboard-as-written.txt dash_as_written
run "q \"the same query, filtered on the partition column\"" 31-dashboard-pruned.txt dash_pruned
run "q \"bytes billed by pipeline label, INFORMATION_SCHEMA.JOBS\"" 32-jobs-by-label.txt \
    q "SELECT l.value AS pipeline, COUNT(*) AS jobs,
              ROUND(SUM(total_bytes_processed) / POW(2, 20), 1) AS processed_mb,
              ROUND(SUM(IFNULL(total_bytes_billed, 0)) / POW(2, 20), 1) AS billed_mb
       FROM \`region-us\`.INFORMATION_SCHEMA.JOBS AS j, UNNEST(j.labels) AS l
       WHERE l.key = 'pipeline' AND j.parent_job_id IS NULL
         AND EXISTS (SELECT 1 FROM UNNEST(j.labels) AS r WHERE r.key = 'run' AND r.value = '$SUFFIX')
         AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
       GROUP BY 1 ORDER BY billed_mb DESC, jobs DESC"
run "gcloud storage buckets update gs://\$BUCKET --lifecycle-file=lifecycle.json" 33-lifecycle.txt \
    bash -c "gcloud storage buckets update gs://$BUCKET --project $PROJECT --lifecycle-file=lifecycle.json 2>&1 | grep -v '^[ .]*$'
             gcloud storage buckets describe gs://$BUCKET --project $PROJECT --format='yaml(default_storage_class,labels,lifecycle_config)'"
run "gcloud storage objects describe \$OLD; objects update --storage-class=NEARLINE; describe again" 34-storage-class.txt \
    bash -c "gcloud storage objects describe $OLD --project $PROJECT --format=json | jq -r '\"gs://\\(.bucket)/\\(.name)  \\(.storage_class)  generation \\(.generation)\"'
             gcloud storage objects update $OLD --project $PROJECT --storage-class=NEARLINE 2>&1 | tail -1
             gcloud storage objects describe $OLD --project $PROJECT --format=json | jq -r '\"gs://\\(.bucket)/\\(.name)  \\(.storage_class)  generation \\(.generation)\"'"
run "gcloud storage cat \$OLD | sed -n 1,3p   (the same URL still serves the file)" 35-same-url.txt \
    bash -c "gcloud storage cat $OLD --project $PROJECT | sed -n '1,3p'"

# ------------------------------------------------------------------ step 8
step "Step 8 · Teardown, and verify nothing is left"
run "gcloud monitoring policies delete \${POLICY:?}; channels delete \${CHANNEL:?}" 36-delete-policy.txt \
    bash -c "gcloud monitoring policies delete ${POLICY:?} --project $PROJECT --quiet 2>&1
             gcloud beta monitoring channels delete ${CHANNEL:?} --project $PROJECT --quiet 2>&1"
run "gcloud logging metrics delete \${METRIC:?}; gcloud logging logs delete \${LOG:?}" 37-delete-metric.txt \
    bash -c "gcloud logging metrics delete ${METRIC:?} --project $PROJECT --quiet 2>&1
             gcloud logging logs delete ${LOG:?} --project $PROJECT --quiet 2>&1"
run "gcloud storage rm -r gs://\${BUCKET:?}" 38-delete-bucket.txt \
    bash -c "gcloud storage rm -r gs://${BUCKET:?} --project $PROJECT 2>&1 | tail -2"
run "bq rm -r -f -d \${DATASET:?}; bq rm -r -f -d \${BACKUP:?}" 39-delete-datasets.txt \
    bash -c "bq --project_id=$PROJECT rm -r -f -d ${DATASET:?} && bq --project_id=$PROJECT rm -r -f -d ${BACKUP:?} && echo 'both datasets removed'"
run "verify: count every resource type whose name carries \$SUFFIX" 40-verify.txt \
    bash -c "printf '%-16s %s\n' 'datasets'  \$(bq --project_id=$PROJECT ls --max_results=1000 | grep -c $SUFFIX)
             printf '%-16s %s\n' 'snapshots' \$(bq --project_id=$PROJECT ls $PROJECT:$BACKUP 2>/dev/null | grep -c SNAPSHOT)
             printf '%-16s %s\n' 'buckets'   \$(gcloud storage ls --project $PROJECT | grep -c $SUFFIX)
             printf '%-16s %s\n' 'log metrics' \$(gcloud logging metrics list --project $PROJECT --format='value(name)' | grep -c $SUFFIX)
             printf '%-16s %s\n' 'logs'      \$(gcloud logging logs list --project $PROJECT | grep -c $SUFFIX)
             printf '%-16s %s\n' 'policies'  \$(gcloud monitoring policies list --project $PROJECT --format='value(displayName)' | grep -c $SUFFIX)
             printf '%-16s %s\n' 'channels'  \$(gcloud beta monitoring channels list --project $PROJECT --format='value(displayName)' | grep -c $SUFFIX)"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ME="$(gcloud config get-value account 2>/dev/null)"
for f in "$OUT"/*.txt; do sed -i '' -e "s/$ME/instructor@example.edu/g" -e "s/$NUMBER/PROJECT_NUMBER/g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
