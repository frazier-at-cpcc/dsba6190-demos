#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 2 demonstration.

    python3 build-notebook.py

    prep.ipynb   create the two datasets and the analyst service account
    demo.ipynb   the hour, steps 1 to 12, teardown included

Commands only, on the Bash kernel. What to say is in RUNBOOK.md.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-02"


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



LOAD = sh(f'source {WORKDIR}/env.sh && echo "$ANALYST" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
READ_RAW = ('as_analyst bq --project_id="$PROJECT" --location=US query --use_legacy_sql=false --format=pretty \\\n'
            '  "SELECT member_id, email, card_number FROM \\`$RAW.loyalty_members\\` LIMIT 3"')
SSH = ('gcloud compute ssh "$VM" --zone "$ZONE" --tunnel-through-iap --quiet --strict-host-key-checking=no')
PROBE = ("for u in https://storage.googleapis.com https://bigquery.googleapis.com https://example.com; do "
         "printf \"%-36s \" $u; curl -s -m 8 -o /dev/null -w \"%{http_code}\\n\" $u || echo \"no route (timed out)\"; done")

notebook("prep", [
    md("# Session 2 · Before class"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    sh('bq --project_id="$PROJECT" ls | grep crown_'),
])

notebook("demo", [
    md("# Session 2 · Grant it wrong, then fix it\n\n"
       "Crown Street Markets, a fictional 40-store Charlotte grocery chain, gives its first analyst "
       "access to store sales. The loyalty table holds card numbers the analyst never needs."),
    LOAD,
    md("## Step 1 · Crown Street's two datasets"),
    sh('bq --project_id="$PROJECT" ls | grep crown_'),
    sh('q "SELECT * FROM \\`$RAW.loyalty_members\\` LIMIT 3"'),
    sh('n=$(as_analyst bq --project_id="$PROJECT" ls --format=json 2>/dev/null | jq length 2>/dev/null)\n'
       'echo "datasets the analyst can see: ${n:-0}"'),
    md("## Step 2 · How big each role is"),
    sh("for r in roles/editor roles/bigquery.dataViewer roles/bigquery.jobUser; do\n"
       "  printf '%-28s %5s permissions\\n' $r $(gcloud iam roles describe $r --format=json | jq '.includedPermissions | length')\n"
       "done"),
    md("## Step 3 · Grant it wrong"),
    sh('gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \\\n'
       '  --role roles/editor --condition=None --quiet | grep -B1 -A2 cs-analyst'),
    sh(f'S=$(date +%s); until {READ_RAW.replace(chr(92)+chr(10), "")} >/dev/null 2>&1; do sleep 10; done\n'
       'echo "took effect after $(( $(date +%s) - S )) s"'),
    md("## Step 4 · What Editor lets the analyst do"),
    sh(READ_RAW),
    sh('as_analyst bq --project_id="$PROJECT" rm -f -t "${RAW:?}.members_backup"'),
    sh('bq --project_id="$PROJECT" ls "$PROJECT:$RAW"'),
    sh('as_analyst gcloud compute instances list'),
    md("## Step 5 · Fix it"),
    sh('gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \\\n'
       '  --role roles/editor --condition=None --quiet >/dev/null && echo "removed roles/editor"\n'
       'gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \\\n'
       '  --role roles/bigquery.jobUser --condition=None --quiet >/dev/null && echo "granted roles/bigquery.jobUser"'),
    sh('q "GRANT \\`roles/bigquery.dataViewer\\` ON SCHEMA \\`$PROJECT.$CURATED\\` TO \'serviceAccount:$ANALYST\'"'),
    md("## Step 6 · Read the policy"),
    sh('gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \\\n'
       '  --filter="bindings.members:$ANALYST" --format="table(bindings.role,bindings.members)"'),
    sh('bq --project_id="$PROJECT" show --format=prettyjson "$PROJECT:$CURATED" | jq -c ".access[]"'),
    md("## Step 7 · Nobody granted this one"),
    sh('gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \\\n'
       '  --filter="bindings.members:-compute@developer.gserviceaccount.com" --format="table(bindings.role,bindings.members)"'),
    sh('gcloud iam service-accounts keys list --iam-account "$ANALYST" \\\n'
       "  --format=\"table(name.basename(),keyType,validAfterTime.date('%Y-%m-%d'))\""),
    md("## Step 8 · A private network"),
    sh('gcloud compute networks create "$NET" --subnet-mode custom'),
    sh('gcloud compute networks subnets create "$SUBNET" --network "$NET" --region "$REGION" --range 10.20.0.0/24'),
    sh('gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-micro --subnet "$SUBNET" --no-address \\\n'
       '  --image-family debian-12 --image-project debian-cloud --shielded-secure-boot --labels course=dsba6190,session=02'),
    sh('gcloud compute firewall-rules list --filter="network:$NET"'),
    sh("until [ \"$(gcloud compute instances describe \"$VM\" --zone \"$ZONE\" --format='value(status)')\" = RUNNING ]; do sleep 5; done\n"
       "sleep 45   # IAP needs the guest to finish booting before it can find the instance"),
    sh(f"time timeout 60 {SSH} --command hostname -- -o ConnectTimeout=20"),
    md("## Step 9 · Open one door"),
    sh('gcloud compute firewall-rules create "$FW" --network "$NET" --direction INGRESS --allow tcp:22 \\\n'
       '  --source-ranges 35.235.240.0/20'),
    sh("cat probe.sh"),
    sh(f"for i in 1 2 3 4 5 6; do\n  timeout 120 {SSH} --command 'bash -s' < probe.sh && break\n  echo \"retrying in 15 s\"; sleep 15\ndone"),
    md("## Step 10 · Private Google Access"),
    sh('gcloud compute networks subnets update "$SUBNET" --region "$REGION" --enable-private-ip-google-access'),
    sh(f"for i in 1 2 3 4 5 6; do\n  timeout 120 {SSH} --command 'bash -s' < probe.sh && break\n  echo \"retrying in 15 s\"; sleep 15\ndone"),
    md("## Step 11 · After: least privilege, scoped"),
    sh(f'S=$(date +%s); while {READ_RAW.replace(chr(92)+chr(10), "")} >/dev/null 2>&1; do sleep 10; done\n'
       'echo "raw table refused; waited $(( $(date +%s) - S )) s more"'),
    sh('as_analyst bq --project_id="$PROJECT" --location=US query --use_legacy_sql=false --format=pretty \\\n'
       '  "SELECT neighborhood, SUM(baskets) AS baskets, ROUND(SUM(revenue_usd)) AS revenue_usd\n'
       '   FROM \\`$CURATED.store_sales\\` GROUP BY 1 ORDER BY 3 DESC LIMIT 5"'),
    sh(READ_RAW),
    sh('as_analyst bq --project_id="$PROJECT" rm -f -t "${CURATED:?}.store_sales"'),
    sh('as_analyst gcloud compute instances list'),
    md("## Step 12 · Teardown"),
    sh('gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet\n'
       'gcloud compute firewall-rules delete "${FW:?}" --quiet\n'
       'gcloud compute networks subnets delete "${SUBNET:?}" --region "${REGION:?}" --quiet\n'
       'gcloud compute networks delete "${NET:?}" --quiet'),
    sh('gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:${ANALYST:?}" \\\n'
       '  --role roles/bigquery.jobUser --condition=None --quiet >/dev/null && echo "removed jobUser"\n'
       'gcloud iam service-accounts delete "${ANALYST:?}" --quiet\n'
       'bq --project_id="$PROJECT" rm -r -f -d "${CURATED:?}"\n'
       'bq --project_id="$PROJECT" rm -r -f -d "${RAW:?}"'),
    sh("gcloud compute networks list --filter='name~crown-net'\n"
       "gcloud iam service-accounts list --filter='email~cs-analyst'\n"
       'bq --project_id="$PROJECT" ls | grep -c crown_ || true'),
])
