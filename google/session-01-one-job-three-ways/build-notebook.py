#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 1 demonstration.

    python3 build-notebook.py

    prep.ipynb   generate the night of trips and stage the bucket
    demo.ipynb   the hour, steps 1 to 12, teardown included

Commands only, on the Bash kernel. What to say is in RUNBOOK.md.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-01"


def notebook(name, parts):
    cells = []
    for kind, text in parts:
        cell = {"cell_type": kind, "metadata": {}, "id": f"{name}-{len(cells):03d}",
                "source": text.strip("\n").splitlines(keepends=True)}
        if kind == "code":
            cell.update(execution_count=None, outputs=[])
        cells.append(cell)
    nb = {"cells": cells,
          "metadata": {"kernelspec": {"display_name": "Bash", "language": "bash", "name": "bash"},
                       "language_info": {"name": "bash", "codemirror_mode": "shell",
                                         "file_extension": ".sh", "mimetype": "text/x-sh"}},
          "nbformat": 4, "nbformat_minor": 5}
    (HERE / f"{name}.ipynb").write_text(json.dumps(nb, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {name}.ipynb: {len(cells)} cells, {sum(c['cell_type'] == 'code' for c in cells)} commands")


def md(t): return ("markdown", t)
def sh(t): return ("code", t)


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$BUCKET" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
RAW = 'gs://$BUCKET/raw/trips-2026-08-19.csv'

notebook("prep", [
    md("# Session 1 · Before class"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    sh(f"gcloud storage ls -l {RAW}"),
])

notebook("demo", [
    md("# Session 1 · One nightly job, three ways\n\n"
       "Queen City Trip Analytics, a fictional South End analytics company, rolls up one night "
       "of a fleet customer's trips before morning."),
    LOAD,
    md("## Step 1 · Who and where"),
    sh("gcloud config list"),
    sh("gcloud auth list --filter=status:ACTIVE"),
    sh('gcloud projects describe "$PROJECT" --format="table(name,projectId,projectNumber,lifecycleState)"'),
    md("## Step 2 · Where the project sits"),
    sh('gcloud projects get-ancestors "$PROJECT"'),
    sh('gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[]" --format="table(bindings.role)"'),
    md("## Step 3 · Geography"),
    sh("gcloud compute regions list --format='value(name)' | wc -l\n"
       "gcloud compute regions list --format='value(name)' | grep '^us-'"),
    sh('gcloud compute zones list --filter="region:us-east1" --format="table(name,status)"'),
    md("## Step 4 · A bucket, and what cannot change"),
    sh('gcloud storage buckets create "gs://$SCRATCH" --location "$REGION" --uniform-bucket-level-access'),
    sh('gcloud storage buckets describe "gs://$SCRATCH" --format="yaml(name,location,location_type,default_storage_class)"'),
    sh('gcloud storage buckets update "gs://$SCRATCH" --location us'),
    sh('gcloud storage buckets update "gs://$SCRATCH" --default-storage-class NEARLINE\n'
       'gcloud storage buckets describe "gs://$SCRATCH" --format="value(default_storage_class)"'),
    md("## Step 5 · Last night's file"),
    sh('gcloud storage ls -l "gs://$BUCKET/raw/"'),
    sh(f'gcloud storage cat -r 0-299 "{RAW}"'),
    sh("cat job/rollup.sh"),
    md("## Step 6 · The job on a virtual machine"),
    sh('V0=$(date +%s)\n'
       'gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-standard-2 \\\n'
       '  --image-family debian-12 --image-project debian-cloud --scopes cloud-platform \\\n'
       '  --labels course=dsba6190,session=01 \\\n'
       '  --metadata startup-script="gcloud storage cat gs://$BUCKET/job/rollup.sh | bash -s $BUCKET vm; shutdown -h now"'),
    sh('until [ "$(gcloud compute instances describe "$VM" --zone "$ZONE" --format=\'value(status)\')" = TERMINATED ]; do sleep 10; done\n'
       'VM_S=$(( $(date +%s) - V0 )); echo "create to TERMINATED: $VM_S s"\n'
       'gcloud compute instances list --filter="name=$VM" --format="table(name,zone.basename(),machineType.basename(),status)"'),
    sh('gcloud storage cat "gs://$BUCKET/out/vm/timing.txt"'),
    sh('gcloud compute disks list --filter="name=$VM" --format="table(name,sizeGb,type.basename(),status,users.len():label=ATTACHED)"'),
    md("## Step 7 · The same job on Cloud Run"),
    sh('gcloud run jobs create "$JOB" --region "$REGION" --image gcr.io/google.com/cloudsdktool/google-cloud-cli:slim \\\n'
       '  --cpu 2 --memory 2Gi --max-retries 0 --task-timeout 15m --labels course=dsba6190,session=01 \\\n'
       '  --command bash --args="-c,gcloud storage cat gs://$BUCKET/job/rollup.sh | bash -s $BUCKET cloud-run"'),
    sh('time gcloud run jobs execute "$JOB" --region "$REGION" --wait'),
    sh('gcloud run jobs executions list --job "$JOB" --region "$REGION" \\\n'
       "  --format=\"table(name,status.succeededCount,status.startTime.date('%H:%M:%S'),status.completionTime.date('%H:%M:%S'))\""),
    sh('gcloud storage cat "gs://$BUCKET/out/cloud-run/timing.txt"'),
    md("## Step 8 · The same question in BigQuery"),
    sh('bq --project_id="$PROJECT" --location=US mk --dataset "$PROJECT:$DATASET"'),
    sh(f'time bq --project_id="$PROJECT" --location=US load --skip_leading_rows=1 "$DATASET.trips" "{RAW}" \\\n'
       '  trip_id:STRING,pickup_ts:DATETIME,pickup_zone:STRING,dropoff_zone:STRING,miles:NUMERIC,fare_usd:NUMERIC,vehicle_id:STRING'),
    sh('q "SELECT pickup_zone, COUNT(*) AS trips, ROUND(SUM(fare_usd), 2) AS revenue_usd\n'
       '   FROM \\`$DATASET.trips\\` GROUP BY 1 ORDER BY 1"'),
    md("## Step 9 · Three platforms, one answer"),
    sh('gcloud storage cat "gs://$BUCKET/out/vm/rollup.csv" > vm.csv\n'
       'gcloud storage cat "gs://$BUCKET/out/cloud-run/rollup.csv" > run.csv\n'
       'bq --project_id="$PROJECT" --location=US query --use_legacy_sql=false --format=csv --quiet \\\n'
       '  "SELECT pickup_zone, COUNT(*), FORMAT(\'%.2f\', CAST(SUM(fare_usd) AS FLOAT64)) FROM \\`$DATASET.trips\\` GROUP BY 1 ORDER BY 1" \\\n'
       '  | tail -n +2 | tr -d \'"\' | sort > bq.csv\n'
       'diff vm.csv run.csv && echo "VM and Cloud Run agree"\n'
       'diff vm.csv bq.csv && echo "VM and BigQuery agree"'),
    md("## Step 10 · What each run cost"),
    sh('EXEC_S=$(gcloud run jobs executions list --job "$JOB" --region "$REGION" --format=json \\\n'
       "  | python3 -c 'import json,sys,datetime as d; e=json.load(sys.stdin)[0][\"status\"]; "
       "f=lambda s: d.datetime.fromisoformat(s.replace(\"Z\",\"+00:00\")); "
       "print(round((f(e[\"completionTime\"])-f(e[\"startTime\"])).total_seconds()))')\n"
       'BQ_BYTES=$(bq --project_id="$PROJECT" --location=US --format=json show -j "$(cat .last_job)" | jq -r \'.statistics.query.totalBytesBilled\')\n'
       'awk -v vm="$VM_S" -v cr="$EXEC_S" -v by="$BQ_BYTES" \'BEGIN {\n'
       '  printf "%-20s %-26s %10s\\n", "platform", "measured", "list price"\n'
       '  printf "%-20s %-26s %10.5f\\n", "Compute Engine", sprintf("%d s of e2-standard-2", vm), vm/3600*0.067006\n'
       '  printf "%-20s %-26s %10.5f\\n", "Cloud Run job", sprintf("%d s of 2 vCPU, 2 GiB", cr), cr*(2*0.000018 + 2*0.000002)\n'
       '  printf "%-20s %-26s %10.5f\\n", "BigQuery on-demand", sprintf("%.0f MB billed", by/1048576), by/1099511627776*6.25 }\''),
    md("## Step 11 · Where cost appears"),
    sh('gcloud billing projects describe "$PROJECT" --format="yaml(billingEnabled)"'),
    sh('gcloud billing budgets list --billing-account="$(gcloud billing projects describe "$PROJECT" --format=\'value(billingAccountName.basename())\')" \\\n'
       '  --format="yaml(displayName,amount,thresholdRules)"'),
    md("## Step 12 · Teardown"),
    sh('gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet\n'
       'gcloud run jobs delete "${JOB:?}" --region "${REGION:?}" --quiet\n'
       'bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"\n'
       'gcloud storage rm -r "gs://${BUCKET:?}" "gs://${SCRATCH:?}" --quiet'),
    sh("gcloud compute instances list --filter='name~qc-nightly'\n"
       "gcloud compute disks list --filter='name~qc-nightly'\n"
       'gcloud run jobs list --region "$REGION"\n'
       'gcloud storage ls | grep -c "$SUFFIX" || true'),
])
