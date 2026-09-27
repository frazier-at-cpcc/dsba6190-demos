# Shell helpers shared with the Session 7 demonstration. Sourced by env.sh, never run.
#
#   dry "<sql>"              price a query without running it. Free.
#   q   "<sql>"              run a query with the cache off, then print what it
#                            processed, what it billed, and the slot time
#   as_analyst <command...>  run one command as the second principal
#   plan                     stages, slot time and shuffle bytes of the last q
#
# Every figure is printed in GB of 2^30 bytes, which is the unit the BigQuery
# editor's estimator uses and the unit the walkthrough quotes.

gb () { awk -v b="${1:-0}" 'BEGIN { printf "%.2f GB", b / 1073741824 }'; }
mb () { awk -v b="${1:-0}" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

dry () {
  local out bytes
  out="$(bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false \
           --dry_run --format=json "$1" 2>&1)" || { echo "$out"; return 1; }
  bytes="$(printf '%s' "$out" | jq -r '.statistics.totalBytesProcessed // "0"')"
  printf 'This query will process %s when run.   (%s bytes)\n' "$(gb "$bytes")" "$bytes"
}

q () {
  local id="dsba6190_$(date +%s)_$RANDOM"
  bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false \
     --nouse_cache --format=pretty --max_rows=20 --job_id="$id" "$1" || return 1
  LAST_JOB="$id"; echo "$id" > "${WORK:-/tmp}/.last_job"
  bq --project_id="$PROJECT" --location=US --format=json show -j "$id" 2>/dev/null \
    | jq -r '.statistics.query | [.totalBytesProcessed // "0", .totalBytesBilled // "0",
                                  .totalSlotMs // "0", .cacheHit // false] | @tsv' \
    | while IFS=$'\t' read -r p b s c; do
        printf 'processed %s · billed %s · slot time %.1f s · cache %s\n' \
          "$(gb "$p")" "$(mb "$b")" "$(awk -v s="$s" 'BEGIN{print s/1000}')" "$c"
      done
}

plan () {
  bq --project_id="$PROJECT" --location=US --format=json show -j "${1:-$(cat "${WORK:-/tmp}/.last_job")}" \
    | jq -r '.statistics.query as $q
      | "slot time      \(($q.totalSlotMs|tonumber)/1000) s",
        "bytes read     \($q.totalBytesProcessed)",
        "",
        "stage                          input rows   output rows   shuffle bytes   parallel",
        ($q.queryPlan[] | [ .name, (.recordsRead // "0"), (.recordsWritten // "0"),
                            (.shuffleOutputBytes // "0"), (.parallelInputs // "0") ]
           | "\(.[0] | .[0:28] | . + (" " * (28 - length)))  \(.[1] | (" " * (12 - length)) + .)  \(.[2] | (" " * (12 - length)) + .)  \(.[3] | (" " * (14 - length)) + .)  \(.[4] | (" " * (9 - length)) + .)")'
}

as_analyst () ( export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$ANALYST"; "$@" )
