#!/usr/bin/env bash
# Capture the Session 1 live demo: one nightly job, three ways.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh into .work/, runs every demonstration step against the
# project, writes each command's output to capture/, and deletes everything
# through an exit trap. Cost: under $0.10. One e2-standard-2 VM for about three
# minutes, one Cloud Run job execution, and 135 MB scanned in BigQuery.
#
# It stages, runs and deletes everything in one pass. To follow the steps
# yourself, prefer prep.ipynb and demo.ipynb.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"; OUT="$HERE/capture"; mkdir -p "$OUT"
export SUFFIX="$(date +%s | tail -c 6)"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () { local label="$1"; local out="$OUT/$2"; shift 2
          { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"; }
cleanup () {
  step "Cleanup"
  gcloud compute instances delete "qc-nightly-vm-$SUFFIX" --zone us-east1-b --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud run jobs delete "qc-nightly-$SUFFIX" --region us-east1 --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" rm -r -f -d "qc_nightly_${SUFFIX:?}" >/dev/null 2>&1 || true
  for b in "qc-nightly-${SUFFIX:?}" "qc-scratch-${SUFFIX:?}"; do
    gcloud storage rm -r "gs://$b" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  done
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"

step "Step 1 · Who and where"
run "gcloud config list" 01-config.txt gcloud config list
run "gcloud auth list --filter=status:ACTIVE" 02-auth.txt gcloud auth list --filter=status:ACTIVE
run "gcloud projects describe \$PROJECT   (name, ID, number)" 03-project.txt \
    gcloud projects describe "$PROJECT" --format="table(name,projectId,projectNumber,lifecycleState)"

step "Step 2 · Where the project sits"
run "gcloud projects get-ancestors \$PROJECT" 04-ancestors.txt gcloud projects get-ancestors "$PROJECT"
run "gcloud projects get-iam-policy \$PROJECT   (roles granted here)" 05-iam.txt \
    gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[]" --format="table(bindings.role)"

step "Step 3 · Geography"
run "gcloud compute regions list | wc -l" 06-regions.txt bash -c \
    "echo \"\$(gcloud compute regions list --format='value(name)' | wc -l | tr -d ' ') regions\"; gcloud compute regions list --format='value(name)' | grep '^us-' | tr '\n' ' '; echo"
run "gcloud compute zones list --filter=region:us-east1" 07-zones.txt \
    gcloud compute zones list --filter="region:us-east1" --format="table(name,status)"

step "Step 4 · A bucket, and what cannot change"
run "gcloud storage buckets create gs://\$SCRATCH --location us-east1" 08-bucket-create.txt \
    gcloud storage buckets create "gs://$SCRATCH" --location "$REGION" --uniform-bucket-level-access
run "gcloud storage buckets describe gs://\$SCRATCH" 09-bucket-describe.txt \
    gcloud storage buckets describe "gs://$SCRATCH" --format="yaml(name,location,location_type,default_storage_class)"
run "gcloud storage buckets update gs://\$SCRATCH --location us   (location is fixed)" 10-bucket-location.txt \
    gcloud storage buckets update "gs://$SCRATCH" --location us
run "gcloud storage buckets update gs://\$SCRATCH --default-storage-class NEARLINE   (class is not)" 11-bucket-class.txt \
    bash -c "gcloud storage buckets update gs://$SCRATCH --default-storage-class NEARLINE && gcloud storage buckets describe gs://$SCRATCH --format='value(default_storage_class)'"

step "Step 5 · Last night's file"
run "gcloud storage ls -l gs://\$BUCKET/raw/" 12-file.txt gcloud storage ls -l "gs://$BUCKET/raw/"
run "gcloud storage cat -r 0-299 gs://\$BUCKET/raw/trips-2026-08-19.csv" 13-head.txt \
    gcloud storage cat -r 0-299 "gs://$BUCKET/raw/trips-2026-08-19.csv"
run "cat job/rollup.sh" 14-rollup.txt cat "$WORK/job/rollup.sh"

step "Step 6 · The job on a virtual machine"
V0=$(date +%s)
run "gcloud compute instances create \$VM --machine-type e2-standard-2 --metadata startup-script=..." 15-vm-create.txt \
    gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-standard-2 \
      --image-family debian-12 --image-project debian-cloud --scopes cloud-platform \
      --labels course=dsba6190,session=01 \
      --metadata startup-script="gcloud storage cat gs://$BUCKET/job/rollup.sh | bash -s $BUCKET vm; shutdown -h now"
until [ "$(gcloud compute instances describe "$VM" --zone "$ZONE" --format='value(status)')" = TERMINATED ]; do sleep 10; done
VM_S=$(( $(date +%s) - V0 ))
run "gcloud compute instances list --filter=name=\$VM   (it stopped itself)" 16-vm-stopped.txt \
    gcloud compute instances list --filter="name=$VM" --format="table(name,zone.basename(),machineType.basename(),status)"
echo "create to TERMINATED: $VM_S s" | tee -a "$OUT/16-vm-stopped.txt"
run "gcloud storage cat gs://\$BUCKET/out/vm/timing.txt" 17-vm-timing.txt gcloud storage cat "gs://$BUCKET/out/vm/timing.txt"
run "gcloud compute disks list --filter=name=\$VM   (the disk is still there)" 18-vm-disk.txt \
    gcloud compute disks list --filter="name=$VM" --format="table(name,sizeGb,type.basename(),status,users.len():label=ATTACHED)"

step "Step 7 · The same job on Cloud Run"
run "gcloud run jobs create \$JOB --image google-cloud-cli:slim --command bash --args=-c,<the same script>" 19-job-create.txt \
    gcloud run jobs create "$JOB" --region "$REGION" --image gcr.io/google.com/cloudsdktool/google-cloud-cli:slim \
      --cpu 2 --memory 2Gi --max-retries 0 --task-timeout 15m --labels course=dsba6190,session=01 \
      --command bash --args="-c,gcloud storage cat gs://$BUCKET/job/rollup.sh | bash -s $BUCKET cloud-run"
run "time gcloud run jobs execute \$JOB --wait" 20-job-execute.txt \
    bash -c "S=\$(date +%s); gcloud run jobs execute $JOB --region $REGION --wait 2>&1 | tail -3; echo \"wall \$(( \$(date +%s) - S )) s\""
run "gcloud run jobs executions list --job \$JOB" 21-job-executions.txt \
    gcloud run jobs executions list --job "$JOB" --region "$REGION" \
      --format="table(name,status.succeededCount,status.startTime.date('%H:%M:%S'),status.completionTime.date('%H:%M:%S'))"
run "gcloud storage cat gs://\$BUCKET/out/cloud-run/timing.txt" 22-job-timing.txt gcloud storage cat "gs://$BUCKET/out/cloud-run/timing.txt"

step "Step 8 · The same question in BigQuery"
run "bq mk --dataset \$DATASET" 23-bq-mk.txt bq --project_id="$PROJECT" --location=US mk --dataset "$PROJECT:$DATASET"
run "time bq load \$DATASET.trips gs://\$BUCKET/raw/trips-2026-08-19.csv" 24-bq-load.txt \
    bash -c "S=\$(date +%s); bq --project_id=$PROJECT --location=US load --skip_leading_rows=1 $DATASET.trips gs://$BUCKET/raw/trips-2026-08-19.csv trip_id:STRING,pickup_ts:DATETIME,pickup_zone:STRING,dropoff_zone:STRING,miles:NUMERIC,fare_usd:NUMERIC,vehicle_id:STRING 2>&1 | tail -1; echo \"wall \$(( \$(date +%s) - S )) s\""
run "q \"SELECT pickup_zone, COUNT(*) trips, SUM(fare_usd) revenue FROM trips GROUP BY 1\"" 25-bq-query.txt \
    q "SELECT pickup_zone, COUNT(*) AS trips, ROUND(SUM(fare_usd), 2) AS revenue_usd FROM \`$DATASET.trips\` GROUP BY 1 ORDER BY 1"

step "Step 9 · Three platforms, one answer"
run "diff the VM, Cloud Run and BigQuery rollups" 26-agree.txt bash -c "
cd \"$WORK\"
gcloud storage cat gs://$BUCKET/out/vm/rollup.csv > vm.csv
gcloud storage cat gs://$BUCKET/out/cloud-run/rollup.csv > run.csv
bq --project_id=$PROJECT --location=US query --use_legacy_sql=false --format=csv --quiet \"SELECT pickup_zone, COUNT(*), FORMAT('%.2f', CAST(SUM(fare_usd) AS FLOAT64)) FROM \\\`$DATASET.trips\\\` GROUP BY 1 ORDER BY 1\" | tail -n +2 | tr -d '\"' | sort > bq.csv
wc -l vm.csv run.csv bq.csv
diff vm.csv run.csv && echo 'VM and Cloud Run agree'
diff vm.csv bq.csv && echo 'VM and BigQuery agree'
head -3 vm.csv"

step "Step 10 · What each run cost"
EXEC_S=$(gcloud run jobs executions list --job "$JOB" --region "$REGION" --format=json \
  | python3 -c 'import json,sys,datetime as d; e=json.load(sys.stdin)[0]["status"]; f=lambda s: d.datetime.fromisoformat(s.replace("Z","+00:00")); print(round((f(e["completionTime"])-f(e["startTime"])).total_seconds()))')
BQ_BYTES=$(bq --project_id="$PROJECT" --location=US --format=json show -j "$(cat "$WORK/.last_job")" | jq -r '.statistics.query.totalBytesBilled')
run "list price of each run, from measured time and bytes" 27-cost.txt bash -c "
awk -v vm=$VM_S -v cr=$EXEC_S -v by=$BQ_BYTES 'BEGIN {
  printf \"%-24s %-28s %10s\n\", \"platform\", \"measured\", \"list price\"
  printf \"%-24s %-28s %10.5f\n\", \"Compute Engine\", sprintf(\"%d s of e2-standard-2\", vm), vm/3600*0.067006
  printf \"%-24s %-28s %10.5f\n\", \"Cloud Run job\", sprintf(\"%d s of 2 vCPU, 2 GiB\", cr), cr*(2*0.000018 + 2*0.000002)
  printf \"%-24s %-28s %10.5f\n\", \"BigQuery on-demand\", sprintf(\"%.0f MB billed\", by/1048576), by/1099511627776*6.25
  printf \"\nThe stopped VM disk still bills: 10 GB standard persistent disk = \$%.2f a month\n\", 10*0.04 }'"

step "Step 11 · Where cost appears"
run "gcloud billing projects describe \$PROJECT" 28-billing.txt \
    gcloud billing projects describe "$PROJECT" --format="yaml(billingEnabled,billingAccountName)"
run "gcloud billing budgets list" 29-budgets.txt bash -c \
    "gcloud billing budgets list --billing-account=\$(gcloud billing projects describe $PROJECT --format='value(billingAccountName.basename())') --format='yaml(displayName,amount,thresholdRules)'"

step "Step 12 · Teardown"
run "delete the VM, the job, the dataset and both buckets" 30-teardown.txt bash -c "
gcloud compute instances delete ${VM:?} --zone ${ZONE:?} --quiet 2>&1 | tail -1
gcloud run jobs delete ${JOB:?} --region ${REGION:?} --quiet 2>&1 | tail -1
bq --project_id=$PROJECT rm -r -f -d ${DATASET:?} && echo 'dataset removed'
gcloud storage rm -r gs://${BUCKET:?} gs://${SCRATCH:?} --quiet 2>&1 | tail -1"
run "verify" 31-verify.txt bash -c "
gcloud compute instances list --filter='name~qc-nightly' 2>&1 | tail -1
gcloud compute disks list --filter='name~qc-nightly' 2>&1 | tail -1
gcloud run jobs list --region $REGION 2>&1 | tail -1
gcloud storage ls 2>/dev/null | grep -c ${SUFFIX:?} || true"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ME="$(gcloud config get-value account 2>/dev/null)"
BA="$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName.basename())')"
for f in "$OUT"/*.txt; do sed -i '' -e "s/$NUMBER/PROJECT_NUMBER/g" -e "s/$ME/instructor@example.edu/g" -e "s/$BA/BILLING_ACCOUNT/g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
