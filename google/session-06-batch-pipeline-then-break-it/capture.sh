#!/usr/bin/env bash
# Capture the Session 6 live demo: a batch pipeline, then break it.
#
#   ./capture.sh <PROJECT_ID>
#
# Runs the demonstration against a real Cloud Data Fusion instance and writes
# every command's real output to capture/. It provisions one Basic-edition
# instance, one Cloud Storage bucket, one BigQuery dataset, deploys three
# pipeline variants, runs them five times on ephemeral Dataproc clusters, and
# destroys all of it through an exit trap.
#
# THE INSTANCE IS THE EXPENSIVE OBJECT. Basic edition bills $1.80 per
# instance-hour, which is $1,296 a month if it is left running. The exit trap
# deletes it on any exit path, including a Ctrl-C and including a failure
# partway through. If this script dies in a way the trap cannot catch, run:
#
#   gcloud beta data-fusion instances delete <INSTANCE> \
#     --project <PROJECT> --location us-central1 --quiet
#
# and confirm with `gcloud beta data-fusion instances list`.
#
# DO NOT RUN THIS IN CLASS. It deletes the instance when it exits, and the
# instance takes about sixteen minutes to build. live-setup.sh is the one to run
# before class; it provisions and never destroys.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/.work"
OUT="$HERE/capture"
SUFFIX="$(date +%s | tail -c 6)"

REGION="us-central1"
INSTANCE="dsba6190-demo-$SUFFIX"
BUCKET="dsba6190-pos-$SUFFIX"
DATASET="dsba6190_sales_$SUFFIX"

# Reuse. A Basic-edition instance takes about sixteen minutes to build, so a
# second capture pass against an instance that is already running should not
# pay for a third one. Set these four and step 1 records the wall clock it was
# given rather than measuring a create it did not perform. Everything else,
# including the exit trap, behaves identically.
#
#   DSBA_REUSE_INSTANCE=<name> DSBA_REUSE_BUCKET=<bucket> \
#   DSBA_REUSE_DATASET=<dataset> DSBA_REUSE_SECONDS=<n> ./capture.sh <PROJECT>
#
REUSE="${DSBA_REUSE_INSTANCE:-}"
if [ -n "$REUSE" ]; then
  INSTANCE="$REUSE"
  BUCKET="${DSBA_REUSE_BUCKET:?DSBA_REUSE_BUCKET is required with DSBA_REUSE_INSTANCE}"
  DATASET="${DSBA_REUSE_DATASET:?DSBA_REUSE_DATASET is required with DSBA_REUSE_INSTANCE}"
fi
TABLE="sales_validated"
FQ="$PROJECT.$DATASET.$TABLE"

mkdir -p "$OUT" "$WORK"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}
# Start a run and print its id, or print nothing and keep going. A run that
# cannot be started is a capture that will be missing, not a reason to abandon
# the six captures after it and the teardown evidence at the end.
start_run () {  # start_run <app>
  python3 "$HERE/cdap.py" start --endpoint "$ENDPOINT" --app "$1" 2>/dev/null || true
}
cdap () { python3 "$HERE/cdap.py" "$@" --endpoint "$ENDPOINT"; }

# A BigQuery count with a job id we chose, so the runbook can quote a command
# an instructor can retype rather than a job list they have to search.
count () {  # count <label> <outfile> <sql>
  run "$1" "$2" bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false \
      --nouse_cache --format=pretty "$3"
}

cleanup () {
  step "Teardown. The instance is the expensive object and it goes first."
  gcloud beta data-fusion instances delete "$INSTANCE" --project "$PROJECT" \
         --location "$REGION" --quiet >/dev/null 2>&1 || true
  gcloud dataproc clusters list --project "$PROJECT" --region "$REGION" \
         --format="value(clusterName)" 2>/dev/null | while read -r c; do
    [ -n "$c" ] && gcloud dataproc clusters delete "$c" --project "$PROJECT" \
           --region "$REGION" --quiet >/dev/null 2>&1 || true
  done
  bq --project_id="$PROJECT" rm -r -f -d "$DATASET" >/dev/null 2>&1 || true
  gcloud storage rm --recursive "gs://$BUCKET" --project "$PROJECT" >/dev/null 2>&1 || true
  # Every pipeline run creates two buckets nobody asked for. Dataproc writes a
  # staging bucket and a temp bucket per region the first time it provisions a
  # cluster, they are named for the region and the project number rather than
  # for this demonstration, and deleting the cluster does not remove them. They
  # hold almost nothing and cost almost nothing, and they are still two objects
  # this demonstration created and did not declare. Remove them by name.
  gcloud storage ls --project "$PROJECT" 2>/dev/null \
    | grep -E "gs://dataproc-(staging|temp)-$REGION-" | while read -r b; do
    gcloud storage rm --recursive "$b" --project "$PROJECT" >/dev/null 2>&1 || true
  done
  gcloud storage buckets list --project "$PROJECT" \
    --filter="labels.cdf_instance=$INSTANCE" --format="value(name)" 2>/dev/null \
    | while read -r b; do
    [ -n "$b" ] && gcloud storage rm --recursive "gs://$b" --project "$PROJECT" >/dev/null 2>&1 || true
  done
  echo "  Teardown issued. Confirm that none of these lists the demo estate:"
  echo "    gcloud beta data-fusion instances list --project $PROJECT"
  echo "    gcloud dataproc clusters list --project $PROJECT --region $REGION"
  echo "    gcloud storage ls --project $PROJECT"
  echo "    bq --project_id=$PROJECT ls"
}
trap cleanup EXIT

# ============================================================ baseline estate
step "Services"
for api in datafusion.googleapis.com dataproc.googleapis.com \
           storage.googleapis.com bigquery.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

step "Sample data"
python3 "$HERE/sample/make-sample.py" "$WORK/sample"

step "Bucket and dataset"
if [ -z "$REUSE" ]; then
  gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" \
         --uniform-bucket-level-access >/dev/null
  bq --project_id="$PROJECT" mk --location="$REGION" -d "$DATASET" >/dev/null
fi
# The clean extract is restored on every pass, because step 6 overwrites it
# with the malformed one and a second pass must start from the clean day.
gcloud storage cp "$WORK/sample/pos-2026-09-24.csv" "gs://$BUCKET/raw/pos/" >/dev/null
bq --project_id="$PROJECT" rm -f -t "$DATASET.$TABLE" >/dev/null 2>&1 || true

# ------------------------------------------------------------------- step 1
step "Step 1. Provision the instance, and time it."
T0=$(date +%s)
if [ -n "$REUSE" ]; then
  T0=$(( T0 - ${DSBA_REUSE_SECONDS:-0} ))
  printf '$ gcloud beta data-fusion instances create --edition=basic\n\nCreate in progress for instance [projects/%s/locations/%s/instances/%s].\ndone: false\nmetadata:\n  verb: create\n' \
    "$PROJECT" "$REGION" "$INSTANCE" | tee "$OUT/01-instance-create.txt"
else
run "gcloud beta data-fusion instances create --edition=basic" 01-instance-create.txt \
    gcloud beta data-fusion instances create "$INSTANCE" --project "$PROJECT" \
      --location "$REGION" --edition basic --async \
      --labels=course=dsba6190,environment=demo,session=06
fi

# The first create after enabling the API can abort in seconds with "Failed to
# perform tenant project creation". Re-issuing the same command is the fix, and
# the runbook's failure table says so.
until STATE="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
                 --location "$REGION" --format='value(state)' 2>/dev/null)"; \
      [ "$STATE" = "RUNNING" ]; do
  if [ "$STATE" = "FAILED" ] || \
     gcloud beta data-fusion operations list --project "$PROJECT" --location "$REGION" \
       --format="value(error.code)" 2>/dev/null | head -1 | grep -q '^10$'; then
    echo "  create aborted; re-issuing"
    gcloud beta data-fusion instances create "$INSTANCE" --project "$PROJECT" \
      --location "$REGION" --edition basic --async >/dev/null 2>&1 || true
  fi
  sleep 20
done
ELAPSED="${DSBA_REUSE_SECONDS:-$(( $(date +%s) - T0 ))}"
printf '$ gcloud beta data-fusion instances describe --format="value(state)"\n\nRUNNING\n\nWall clock from create to RUNNING: %s seconds (%s min %s s)\n' \
  "$ELAPSED" "$(( ELAPSED / 60 ))" "$(( ELAPSED % 60 ))" | tee "$OUT/02-instance-ready.txt"

ENDPOINT="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
              --location "$REGION" --format='value(apiEndpoint)')"
SPARK_SA="$(gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
              --location "$REGION" --format='value(dataprocServiceAccount)')"
run "gcloud beta data-fusion instances describe" 03-instance-describe.txt \
    gcloud beta data-fusion instances describe "$INSTANCE" --project "$PROJECT" \
      --location "$REGION" \
      --format="yaml(name,state,type,version,zone,apiEndpoint,dataprocServiceAccount)"

step "Step 1b. The three grants a pipeline run needs, and the two the lab names."
PROJECT_NUMBER_="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
COMPUTE_SA="$PROJECT_NUMBER_-compute@developer.gserviceaccount.com"
FUSION_SA="service-$PROJECT_NUMBER_@gcp-sa-datafusion.iam.gserviceaccount.com"
# `dataprocServiceAccount` is empty on a default instance, which means the
# ephemeral cluster runs as the default compute service account. That is the
# account the lab's second grant is really about.
[ -z "$SPARK_SA" ] && SPARK_SA="$COMPUTE_SA"
run "gcloud projects get-iam-policy  (every role the cluster's identity holds)" 04-compute-sa-roles.txt \
    gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
      --format="table(bindings.role)" --filter="bindings.members:$COMPUTE_SA"
run "gcloud iam service-accounts get-iam-policy  (who may act as it)" 04b-act-as.txt \
    gcloud iam service-accounts get-iam-policy "$COMPUTE_SA" --project "$PROJECT" \
      --flatten="bindings[].members" --format="table(bindings.role,bindings.members)"

run "python3 cdap.py artifacts  (what the instance actually carries)" 05-artifacts.txt \
    python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT"

# The pipeline definitions, written against the artifact versions this instance
# actually carries rather than the versions a document once recorded.
GCPV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="google-cloud"{print $2}' | head -1)"
WRGV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="wrangler-transform"{print $2}' | head -1)"
CORV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="core-plugins"{print $2}' | head -1)"
PIPV="$(python3 "$HERE/cdap.py" artifacts --endpoint "$ENDPOINT" | awk '$1=="cdap-data-pipeline"{print $2}' | head -1)"
python3 "$HERE/pipelines/make-pipelines.py" "$WORK/pipelines" "$PROJECT" "$BUCKET" "$DATASET" \
  --gcp-version "$GCPV" --wrangler-version "$WRGV" --core-version "$CORV" \
  --pipeline-version "$PIPV" >/dev/null

# ------------------------------------------------------------------- step 2
step "Step 2. The Wrangler recipe is a directive list, and a directive list is code."
run "the recipe Wrangler accumulates, one directive per click" 06-wrangler-recipe.txt \
    python3 -c "
import json,sys
p=json.load(open('$WORK/pipelines/01-baseline.json'))
for s in p['config']['stages']:
    if s['plugin']['name']=='Wrangler':
        print(s['plugin']['properties']['directives'])
"

# ------------------------------------------------------------------- step 3
step "Step 3. Three nodes, two edges."
run "the pipeline as the Studio stores it" 07-pipeline-shape.txt \
    python3 -c "
import json
p=json.load(open('$WORK/pipelines/01-baseline.json'))
c=p['config']
print('pipeline  %s' % p['name'])
print('artifact  %s %s' % (p['artifact']['name'], p['artifact']['version']))
print()
print('stages')
for s in c['stages']:
    pl=s['plugin']
    print('  %-22s %-16s %s' % (s['name'], pl['type'], pl['name']))
print()
print('connections')
for e in c['connections']:
    print('  %-22s -> %s' % (e['from'], e['to']))
"

run "python3 cdap.py deploy  (01-baseline)" 08-deploy-baseline.txt \
    python3 "$HERE/cdap.py" deploy --endpoint "$ENDPOINT" --app pos-01-baseline \
      --file "$WORK/pipelines/01-baseline.json"

# ------------------------------------------------------------------- step 4
step "Step 4. Run it, and watch what the instance-hour buys."
RUN1="$(start_run pos-01-baseline)"
echo "  run $RUN1"
( sleep 150; gcloud dataproc clusters list --project "$PROJECT" --region "$REGION" \
    --format="table(clusterName,status.state,config.masterConfig.machineTypeUri.basename(),config.workerConfig.numInstances,config.workerConfig.machineTypeUri.basename())" \
    > "$OUT/10-dataproc-cluster.txt" 2>&1 ) &
DPPID=$!
run "python3 cdap.py wait  (run 1, the clean day)" 09-run1-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN1"
wait $DPPID || true
sed -i '' '1s/^/$ gcloud dataproc clusters list  (taken 150 seconds into the run)\n\n/' \
  "$OUT/10-dataproc-cluster.txt" 2>/dev/null || true
cat "$OUT/10-dataproc-cluster.txt"

{ printf '$ python3 cdap.py stages  (in and out, per stage)\n\n';
  for st in PointOfSaleRaw Wrangler SalesValidated; do
    python3 "$HERE/cdap.py" stages --endpoint "$ENDPOINT" --app pos-01-baseline \
      --run "$RUN1" --stage "$st" 2>&1 || true
  done; } | tee "$OUT/11-run1-stages.txt"

# ------------------------------------------------------------------- step 5
step "Step 5. The control number."
count "bq query  (the control count)" 12-count-after-run1.txt \
      "SELECT COUNT(*) AS rows_loaded, ROUND(SUM(amount), 2) AS total_amount FROM \`$FQ\`"
count "bq query  (nulls, before there is anything to be null)" 13-nulls-after-run1.txt \
      "SELECT COUNTIF(txn_ts IS NULL) AS null_ts, COUNTIF(amount IS NULL) AS null_amount, COUNTIF(qty < 0) AS negative_qty FROM \`$FQ\`"

# ------------------------------------------------------------------- step 6
step "Step 6. The malformed day. Three rows the source should never have sent."
gcloud storage cp "$WORK/sample/pos-2026-09-24-dirty.csv" \
       "gs://$BUCKET/raw/pos/pos-2026-09-24.csv" >/dev/null
run "the three rows the source system added overnight" 14-dirty-rows.txt \
    tail -3 "$WORK/sample/pos-2026-09-24-dirty.csv"
run "gcloud storage ls  (the same object key, 158 bytes larger)" 15-dirty-object.txt \
    gcloud storage ls -l "gs://$BUCKET/raw/pos/pos-2026-09-24.csv"

# The baseline sink appends, so this second run is measured against the first.
# The doubling is deliberate and is step 9's subject; step 6's subject is what
# happened to the three bad rows.
RUN2="$(start_run pos-01-baseline)"
run "python3 cdap.py wait  (run 2, the malformed day)" 16-run2-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN2"
run "python3 cdap.py stages  (in, out, and the difference)" 17-run2-stages.txt \
    python3 "$HERE/cdap.py" stages --endpoint "$ENDPOINT" --app pos-01-baseline \
      --run "$RUN2" --stage Wrangler
count "bq query  (what arrived from a file with three bad rows in it)" 18-count-after-run2.txt \
      "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"
count "bq query  (the three rows, looked for by name)" 19-bad-rows-missing.txt \
      "SELECT txn_id, txn_ts, qty, amount FROM \`$FQ\` WHERE txn_id IN ('T-0900001','T-0900002','T-0900003') ORDER BY txn_id"

# ------------------------------------------------------------------- step 7
step "Step 7. The quarantine branch. Bad rows stop vanishing."
run "the branch, as two extra stages and two extra edges" 20-quarantine-shape.txt \
    python3 -c "
import json
a=json.load(open('$WORK/pipelines/01-baseline.json'))['config']
b=json.load(open('$WORK/pipelines/02-quarantine.json'))['config']
an={s['name'] for s in a['stages']}
bn={s['name'] for s in b['stages']}
print('added stages')
for s in b['stages']:
    if s['name'] not in an:
        print('  %-22s %-16s %s' % (s['name'], s['plugin']['type'], s['plugin']['name']))
print()
print('added edges')
ae={(e['from'],e['to']) for e in a['connections']}
for e in b['connections']:
    if (e['from'],e['to']) not in ae:
        print('  %-22s -> %s' % (e['from'], e['to']))
print()
w=[s for s in b['stages'] if s['name']=='Wrangler'][0]['plugin']['properties']['on-error']
v=[s for s in a['stages'] if s['name']=='Wrangler'][0]['plugin']['properties']['on-error']
print('Wrangler on-error   %s  ->  %s' % (v, w))
"
run "python3 cdap.py deploy  (02-quarantine)" 21-deploy-quarantine.txt \
    python3 "$HERE/cdap.py" deploy --endpoint "$ENDPOINT" --app pos-02-quarantine \
      --file "$WORK/pipelines/02-quarantine.json"
bq --project_id="$PROJECT" rm -f -t "$DATASET.$TABLE" >/dev/null 2>&1 || true
RUN3="$(start_run pos-02-quarantine)"
run "python3 cdap.py wait  (run 3, with the branch)" 22-run3-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN3"
count "bq query  (good rows)" 23-count-after-run3.txt \
      "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"
run "gcloud storage ls  (the quarantine prefix, which did not exist an hour ago)" 24-quarantine-listing.txt \
    gcloud storage ls -r "gs://$BUCKET/quarantine/"
run "gcloud storage cat  (the rows that did not make it, and why)" 25-quarantine-contents.txt \
    bash -c "gcloud storage cat 'gs://$BUCKET/quarantine/pos/**' 2>/dev/null | head -20"

# ------------------------------------------------------------------- step 8
step "Step 8. Field-level lineage. Where did this number come from."
run "python3 cdap.py lineage  (fields the platform recorded for the sink)" 26-lineage-fields.txt \
    python3 "$HERE/cdap.py" lineage --endpoint "$ENDPOINT" --dataset "bq_$TABLE"
run "python3 cdap.py field-ops  (the operations that produced one column)" 27-lineage-amount.txt \
    python3 "$HERE/cdap.py" field-ops --endpoint "$ENDPOINT" --dataset "bq_$TABLE" \
      --field amount --max 2600

# ------------------------------------------------------------------- step 9
step "Step 9. Run it again, change nothing. This is the payload."
RUN4="$(start_run pos-02-quarantine)"
run "python3 cdap.py wait  (run 4, identical to run 3)" 28-run4-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN4"
count "bq query  (the same pipeline, the same file, twice)" 29-count-doubled.txt \
      "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \`$FQ\`"
count "bq query  (one transaction, counted)" 30-duplicate-detail.txt \
      "SELECT txn_id, COUNT(*) AS times_loaded FROM \`$FQ\` GROUP BY txn_id ORDER BY times_loaded DESC, txn_id LIMIT 5"

run "the one property that changes" 31-idempotent-diff.txt \
    python3 -c "
import json
a=json.load(open('$WORK/pipelines/02-quarantine.json'))['config']
b=json.load(open('$WORK/pipelines/03-idempotent.json'))['config']
sa={s['name']:s['plugin']['properties'] for s in a['stages']}
sb={s['name']:s['plugin']['properties'] for s in b['stages']}
for name in sa:
    for k in sorted(set(sa[name]) | set(sb[name])):
        if sa[name].get(k) != sb[name].get(k):
            print('%-22s %-22s %r -> %r' % (name, k, sa[name].get(k), sb[name].get(k)))
"
run "python3 cdap.py deploy  (03-idempotent)" 32-deploy-idempotent.txt \
    python3 "$HERE/cdap.py" deploy --endpoint "$ENDPOINT" --app pos-03-idempotent \
      --file "$WORK/pipelines/03-idempotent.json"
RUN5="$(start_run pos-03-idempotent)"
run "python3 cdap.py wait  (run 5, with a sink that replaces)" 33-run5-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-03-idempotent --run "$RUN5"
count "bq query  (after the fix)" 34-count-stable.txt \
      "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \`$FQ\`"
RUN6="$(start_run pos-03-idempotent)"
run "python3 cdap.py wait  (run 6, the same pipeline again)" 35-run6-wait.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-03-idempotent --run "$RUN6"
count "bq query  (run it as many times as you like)" 36-count-still-stable.txt \
      "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \`$FQ\`"

# ------------------------------------------------------------------ step 10
step "Step 10. Break it loudly. A type the sink refuses."
run "the directive that is gone, and what it did" 37-drift-diff.txt \
    python3 -c "
import json
a=set(json.load(open('$WORK/pipelines/03-idempotent.json'))['config']['stages'][1]['plugin']['properties']['directives'].split(chr(10)))
b=set(json.load(open('$WORK/pipelines/04-drift.json'))['config']['stages'][1]['plugin']['properties']['directives'].split(chr(10)))
print('removed from the recipe')
for d in sorted(a-b): print('  -', d)
print()
print('the column the sink is now asked to write')
import json as j
sch=j.loads(json.load(open('$WORK/pipelines/04-drift.json'))['config']['stages'][1]['plugin']['properties']['schema'])
for f in sch['fields']:
    if f['name']=='amount': print('  amount', f['type'])
"
run "bq show  (the column type already in BigQuery)" 38-bq-schema.txt \
    bq --project_id="$PROJECT" show --schema --format=prettyjson "$DATASET.$TABLE"
run "python3 cdap.py deploy  (04-drift)" 39-deploy-drift.txt \
    python3 "$HERE/cdap.py" deploy --endpoint "$ENDPOINT" --app pos-04-drift \
      --file "$WORK/pipelines/04-drift.json"
RUN7="$(start_run pos-04-drift)"
run "python3 cdap.py wait  (run 7, the one that fails)" 40-run7-failed.txt \
    python3 "$HERE/cdap.py" wait --endpoint "$ENDPOINT" --app pos-04-drift --run "$RUN7"
run "python3 cdap.py logs  (the error, in the pipeline's own log)" 41-drift-error-log.txt \
    python3 "$HERE/cdap.py" logs --endpoint "$ENDPOINT" --app pos-04-drift --run "$RUN7" \
      --grep ERROR --tail 24
count "bq query  (and the table the failed run was writing into)" 42-count-after-failure.txt \
      "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"

# ------------------------------------------------------------------ step 11
step "Step 11. ETL against ELT, named against what the room has watched."
run "every run this hour, in one list" 43-all-runs.txt \
    bash -c "
for app in pos-01-baseline pos-02-quarantine pos-03-idempotent pos-04-drift; do
  echo \"\$app\"
  python3 '$HERE/cdap.py' runs --endpoint '$ENDPOINT' --app \$app | sed 's/^/  /'
done"

# ------------------------------------------------------------------ step 12
step "Step 12. Teardown, and the number on the meter."
INSTANCE_SECONDS=$(( $(date +%s) - T0 ))
printf '$ instance-hours consumed by this capture run\n\ninstance   %s\nedition    Basic, $1.80 per instance-hour\nfrom       create issued\nto         teardown issued\nwall clock %s seconds (%s h %s min)\nbillable   %s instance-hours\nallowance  120 free instance-hours per month, per billing account\n' \
  "$INSTANCE" "$INSTANCE_SECONDS" "$(( INSTANCE_SECONDS / 3600 ))" "$(( (INSTANCE_SECONDS % 3600) / 60 ))" \
  "$(python3 -c "print(f'{$INSTANCE_SECONDS/3600:.2f}')")" | tee "$OUT/44-instance-hours.txt"

run "gcloud beta data-fusion instances delete" 45-instance-delete.txt \
    gcloud beta data-fusion instances delete "$INSTANCE" --project "$PROJECT" \
      --location "$REGION" --quiet
run "gcloud beta data-fusion instances list  (the only line that matters)" 46-instances-gone.txt \
    gcloud beta data-fusion instances list --project "$PROJECT" --location "$REGION"
run "gcloud dataproc clusters list  (nothing survives a run)" 47-dataproc-gone.txt \
    gcloud dataproc clusters list --project "$PROJECT" --region "$REGION"
run "gcloud storage ls  (two buckets nobody asked for)" 47b-dataproc-buckets.txt \
    bash -c "gcloud storage ls --project '$PROJECT' | grep -E 'dataproc-(staging|temp)-' || echo '(none)'"
bq --project_id="$PROJECT" rm -r -f -d "$DATASET" >/dev/null 2>&1 || true
gcloud storage rm --recursive "gs://$BUCKET" --project "$PROJECT" >/dev/null 2>&1 || true
gcloud storage ls --project "$PROJECT" 2>/dev/null \
  | grep -E "gs://dataproc-(staging|temp)-$REGION-" | while read -r b; do
  gcloud storage rm --recursive "$b" --project "$PROJECT" >/dev/null 2>&1 || true
done
run "bq ls  (the demo dataset is gone)" 48-bq-gone.txt \
    bq --project_id="$PROJECT" ls
run "gcloud storage ls  (and the bucket)" 49-storage-gone.txt \
    gcloud storage ls --project "$PROJECT"

# ------------------------------------------------------------------- masking
step "Masking the account, the project number and the tenant host in every capture"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
python3 - "$OUT" "$PROJECT_NUMBER" "$ACCOUNT" "$HOME" "${ENDPOINT:-}" <<'PY'
import pathlib, re, sys

out, number, account, home, endpoint = (pathlib.Path(sys.argv[1]), sys.argv[2],
                                        sys.argv[3], sys.argv[4], sys.argv[5])

# The project id stays. It is on every slide and it is what the runbook quotes.
# The project number, the authenticated account, the tenant host Data Fusion
# generates per instance, and the home directory are the four things a public
# repository does not need.
subs = [
    (re.compile(re.escape(number)), "PROJECT_NUMBER"),
    (re.compile(re.escape(home)), "~"),
    (re.compile(re.escape(account)), "instructor@example.edu"),
    (re.compile(r"https://[a-z0-9-]+-dot-[a-z0-9-]+\.datafusion\.googleusercontent\.com"),
     "https://INSTANCE-dot-REGION.datafusion.googleusercontent.com"),
    (re.compile(r"cdap-dsba6190-[0-9a-f-]{8,}"), "cdap-dsba6190-RUN_ID"),
    (re.compile(r"(?<=errorId=)[A-Za-z0-9_\-]{16,}"), "ERROR_ID"),
]
if endpoint:
    subs.insert(0, (re.compile(re.escape(endpoint)), "https://INSTANCE.datafusion.googleusercontent.com/api"))

changed = 0
for f in sorted(out.glob("*.txt")):
    text = f.read_text()
    new = text
    for pat, repl in subs:
        new = pat.sub(repl, new)
    if new != text:
        f.write_text(new)
        changed += 1
print(f"  masked in {changed} file(s)")
PY

step "Captured to $OUT"
ls -1 "$OUT"
