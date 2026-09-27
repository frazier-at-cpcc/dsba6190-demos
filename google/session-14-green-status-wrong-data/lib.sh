# Shell helpers for the Session 14 demonstration. Sourced by env.sh, never run.
#
#   q "<sql>"               run a query with the cache off, then print what it
#                           processed and billed. PIPELINE=<name> sets its label
#   nightly_load <gs://uri> replace last night's partition of store_sales with
#                           one file, exactly as the nightly job does
#   checks                  run the four data checks in sql/checks.sql
#   log_checks              run them again and write each result to Cloud
#                           Logging as one structured JSON entry
#   red_count               read the log-based metric's recent points
#
# Every job carries two labels: pipeline, which the FinOps step groups by, and
# run, which keeps this run's jobs apart from every other job in the project.
# The leading space on each query stops bq reading a leading -- comment as a flag.

mb () { awk -v b="${1:-0}" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

q () {
  local id="s14_$(date +%s)_$RANDOM"
  bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false \
     --nouse_cache --format=pretty --max_rows=20 --job_id="$id" \
     --label="pipeline:${PIPELINE:-adhoc}" --label="run:$SUFFIX" " $1" || return 1
  bq --project_id="$PROJECT" --location=US --format=json show -j "$id" 2>/dev/null \
    | jq -r '.statistics.query // {} | [.totalBytesProcessed // "0", .totalBytesBilled // "0"] | @tsv' \
    | while IFS=$'\t' read -r p b; do
        printf 'processed %s · billed %s · label pipeline:%s\n' "$(mb "$p")" "$(mb "$b")" "${PIPELINE:-adhoc}"
      done
}

nightly_load () {
  local id="s14_load_$(date +%s)_$RANDOM"
  bq --project_id="$PROJECT" --location=US --quiet load --job_id="$id" \
     --label=pipeline:nightly_load --label="run:$SUFFIX" \
     --source_format=CSV --skip_leading_rows=1 --autodetect --source_column_match=NAME \
     --schema_update_option=ALLOW_FIELD_ADDITION --replace \
     "$PROJECT:$DATASET.store_sales\$$LAST_ID" "${1:?usage: nightly_load gs://bucket/file.csv}" || return 1
  bq --project_id="$PROJECT" --location=US --format=json show -j "$id" \
    | jq -r '"load job   \(.jobReference.jobId)",
             "state      \(.status.state)",
             "errors     \(.status.errorResult.message // "none")",
             "rows       \(.statistics.load.outputRows)",
             "into       store_sales$\(env.LAST_ID)"'
}

checks () { PIPELINE=dq_checks q "$(sed "s/@@DS@@/$DS/g" "$WORK/sql/checks.sql")"; }

log_checks () {
  local rows
  rows="$(bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false --nouse_cache \
            --format=json --label=pipeline:dq_checks --label="run:$SUFFIX" \
            " $(sed "s/@@DS@@/$DS/g" "$WORK/sql/checks.sql")")" || return 1
  printf '%s' "$rows" | jq -c '.[] | . + {table: "store_sales", sale_date: env.LAST_NIGHT}' \
    | while read -r entry; do
        sev=INFO; [ "$(printf '%s' "$entry" | jq -r .status)" = RED ] && sev=ERROR
        gcloud logging write "$LOG" "$entry" --payload-type=json --severity="$sev" \
               --project "$PROJECT" >/dev/null 2>&1 && printf '%-5s  %s\n' "$sev" "$entry"
      done
}

red_count () {
  curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" -G \
    "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries" \
    --data-urlencode "filter=metric.type=\"logging.googleapis.com/user/$METRIC\"" \
    --data-urlencode "interval.startTime=$(date -u -v-15M +%FT%TZ)" \
    --data-urlencode "interval.endTime=$(date -u +%FT%TZ)" \
  | jq -r '.timeSeries[]? | .metric.labels.check as $c | .points[]
           | select(.value.int64Value != "0") | "\(.interval.endTime)  check=\($c)  RED results=\(.value.int64Value)"'
}
