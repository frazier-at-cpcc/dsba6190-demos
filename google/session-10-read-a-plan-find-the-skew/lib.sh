# shellcheck shell=bash disable=SC2034
# Shell helpers for the Session 10 demonstration. Sourced by env.sh, never run.
#
#   submit  <name> <mode> [props] [rows]  submit a batch with --async and return at once
#   waitfor <name>                        poll until that batch ends, then print its state,
#                                         its run time, and the job's result line
#   batch   <name> <mode> [props] [rows]  submit, then wait. What capture.sh and prep use
#   planof  <name>                        print the physical plan the variant wrote
#   evlog   <name>                        fetch the variant's event log, print the stage table
#   biggest <name>                        the largest single task in each stage that reads a shuffle
#   finalplan <name>                      the plan adaptive query execution actually ran
#   apptime <name>                        how long the Spark application itself ran
#   bqq     "<sql>"                       run a query with the cache off, then print slot time,
#                                         bytes processed and stage count
#
# The properties match capture.sh exactly: runtime 2.2, uncompressed event logs,
# dynamic allocation off, two executors of four cores, 200 shuffle partitions.
# Each batch holds 12 vCPUs. submit waits for this demo's previous batch to
# finish before it starts the next, so the demonstration never needs more than
# 12 of the project's CPUS_ALL_REGIONS quota. Three overlapping batches need 36.

COMMON="spark.eventLog.enabled=true,spark.eventLog.compress=false,spark.eventLog.dir=$BASE/eventlogs,spark.dynamicAllocation.enabled=false,spark.executor.instances=2,spark.executor.cores=4,spark.sql.shuffle.partitions=200"
OFF="spark.sql.adaptive.enabled=false,spark.sql.autoBroadcastJoinThreshold=-1"
AQE_ON="spark.sql.adaptive.enabled=true,spark.sql.adaptive.skewJoin.enabled=true,spark.sql.autoBroadcastJoinThreshold=-1"

submit () {
  local id out busy
  while busy="$(gcloud dataproc batches list --project "$PROJECT" --region "$REGION" \
                  --format='value(name.basename(),state)' 2>/dev/null \
                | awk -v s="-$SUFFIX-" 'index($1, s) && ($2 == "PENDING" || $2 == "RUNNING") { print $1; exit }')" \
        && [ -n "$busy" ]; do
    echo "waiting for $busy to finish, so this batch fits in the vCPU quota"; sleep 15
  done
  id="qc-$1-$SUFFIX-$(date +%H%M%S)"
  out="$(gcloud dataproc batches submit pyspark "$BASE/jobs/billing.py" --project "$PROJECT" --region "$REGION" \
          --batch "$id" --version 2.2 --properties "$COMMON${3:+,$3}" --async -- "$2" "$BASE" ${4:-} 2>&1)" \
    || { printf '%s\n' "$out" | tail -5; echo "submit failed for $1"; return 1; }
  echo "$id" > "$WORK/$1.id"; echo "$2" > "$WORK/$1.mode"
  echo "submitted $id"
}

waitfor () {
  local id mode state times uri n=0
  id="$(cat "$WORK/$1.id")"; mode="$(cat "$WORK/$1.mode")"
  until state="$(gcloud dataproc batches describe "$id" --project "$PROJECT" --region "$REGION" \
                   --format='value(state)' 2>/dev/null)" \
        && [[ "$state" =~ ^(SUCCEEDED|FAILED|CANCELLED)$ ]]; do
    n=$((n + 1)); [ "$n" -gt 90 ] && { echo "$1 still ${state:-unknown} after 15 minutes"; return 1; }
    sleep 10
  done
  times="$(gcloud dataproc batches describe "$id" --project "$PROJECT" --region "$REGION" \
             --format='value(createTime,stateTime)')"
  echo "$1: $state, $(python3 -c '
import re, sys, datetime as d
f = lambda s: d.datetime.strptime(re.sub(r"\.\d+", "", s).replace("Z", ""), "%Y-%m-%dT%H:%M:%S")
c, s = sys.argv[1].split()
print(int((f(s) - f(c)).total_seconds()))' "$times") s from create to finish"
  uri="$(gcloud dataproc batches describe "$id" --project "$PROJECT" --region "$REGION" \
           --format='value(runtimeInfo.outputUri)' 2>/dev/null)"
  [ -n "$uri" ] && gcloud storage cat "${uri}*" 2>/dev/null | grep -E "^(generated|$mode:)" || true
  [ "$state" = "SUCCEEDED" ]
}

batch () { submit "$@" && waitfor "$1"; }

planof () { gcloud storage cat "$BASE/plans/$(cat "$WORK/$1.mode")/part-*"; }

logof () {  # logof <name>: path of the newest finished event log for that variant
  local mode f
  mode="$(cat "$WORK/$1.mode")"
  mkdir -p "$WORK/eventlogs"
  gcloud storage cp -n "$BASE/eventlogs/*" "$WORK/eventlogs/" >/dev/null 2>&1 || true
  f="$(grep -l "\"App Name\":\"qc-billing-$mode\"" "$WORK"/eventlogs/app-* 2>/dev/null \
         | grep -v inprogress | sort | tail -1)"
  [ -n "$f" ] || { echo "no finished event log for $mode yet" >&2; return 1; }
  echo "$f"
}

evlog () { local f; f="$(logof "$1")" && python3 "$WORK/stages.py" "$f"; }

apptime () { local f; f="$(logof "$1")" && python3 "$WORK/stages.py" --app-time "$f"; }

finalplan () { local f; f="$(logof "$1")" && python3 "$WORK/stages.py" --final-plan "$f"; }

biggest () {  # biggest <name>: the largest single task in each shuffle-reading stage
  local f; f="$(logof "$1")" && python3 "$WORK/stages.py" --largest "$f"
}

bqq () {
  local id
  id="qc_${SUFFIX}_$(date +%s)_$RANDOM"
  bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false --nouse_cache \
     --format=pretty --job_id="$id" "$1" || return 1
  bq --project_id="$PROJECT" --location=US --format=json show -j "$id" | python3 -c '
import json, sys
q = json.load(sys.stdin)["statistics"]["query"]
print("slot time", round(int(q.get("totalSlotMs", 0)) / 1000, 1), "s · processed",
      round(int(q.get("totalBytesProcessed", 0)) / 2**20, 1), "MB · stages", len(q.get("queryPlan", [])))'
}
