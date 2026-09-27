#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 6 demonstration.

    python3 build-notebook.py

    prep.ipynb   before you start: provision, verify, smoke run, clean up
    demo.ipynb   steps 1 to 12, then the teardown

Both run on the Bash kernel (`python3 -m pip install bash_kernel`, then
`python3 -m bash_kernel.install`), so every cell is the command exactly as it
would be typed in a terminal and shell variables persist between cells. The
notebooks carry step headings and commands only. The walkthrough is in
RUNBOOK.md. Regenerate after editing the runbook so the two stay in step.
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-06"


def notebook(name, parts):
    cells = []
    for kind, text in parts:
        src = text.strip("\n").splitlines(keepends=True)
        cell = {"cell_type": kind, "metadata": {}, "source": src,
                "id": f"{name}-{len(cells):03d}"}
        if kind == "code":
            cell.update(execution_count=None, outputs=[])
        cells.append(cell)
    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Bash", "language": "bash", "name": "bash"},
            "language_info": {"name": "bash", "codemirror_mode": "shell",
                              "file_extension": ".sh", "mimetype": "text/x-sh"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    out = HERE / f"{name}.ipynb"
    out.write_text(json.dumps(nb, indent=1, ensure_ascii=False) + "\n")
    n = sum(c["cell_type"] == "code" for c in cells)
    print(f"wrote {out.name}: {len(cells)} cells, {n} commands")


def md(text):
    return ("markdown", text)


def sh(text):
    return ("code", text)


LOAD = sh(f"""
source {WORKDIR}/env.sh || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."
WORK="${{WORK:-$HOME/dsba6190-live-demo-06}}"
echo "$INSTANCE   $BUCKET   $FQ"
""")

BQ = 'bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty'

# ---------------------------------------------------------------- prep.ipynb
notebook("prep", [
    md("# Session 6 · Before you start"),

    md("## Provision"),
    sh('./live-setup.sh YOUR_PROJECT_ID'),
    LOAD,

    md("## Verify the plugin artifacts"),
    sh('python3 cdap.py artifacts --endpoint "$ENDPOINT"'),

    md("## Smoke run"),
    sh('python3 cdap.py deploy --endpoint "$ENDPOINT" --app smoke \\\n'
       '  --file "$WORK/pipelines/01-baseline.json"'),
    sh('SMOKE=$(python3 cdap.py start --endpoint "$ENDPOINT" --app smoke)\n'
       'python3 cdap.py wait --endpoint "$ENDPOINT" --app smoke --run "$SMOKE"'),

    md("## Clean up the smoke run"),
    sh('python3 cdap.py delete --endpoint "$ENDPOINT" --app smoke\n'
       'bq --project_id="${PROJECT:?}" rm -f -t "${DATASET:?}.sales_validated"\n'
       'gcloud dataproc clusters list --project "$PROJECT" --region us-central1'),

    md("## Studio URL"),
    sh('echo "$CONSOLE"'),
])

# ---------------------------------------------------------------- demo.ipynb
notebook("demo", [
    md("# Session 6 · A batch pipeline, then break it\n\n"
       "Crown Street Markets, a fictional Charlotte grocery chain with 40 stores, "
       "builds the sales table its store managers read at 7 a.m."),
    LOAD,

    md("## Step 1 · The instance, the edition, and the meter"),
    sh('gcloud beta data-fusion instances describe "$INSTANCE" \\\n'
       '  --project "$PROJECT" --location us-central1 \\\n'
       '  --format="yaml(name,state,type,version,apiEndpoint)"'),

    md("## Step 2 · The recipe is a directive list"),
    sh('echo "gs://$BUCKET/raw/pos/pos-2026-09-24.csv"'),

    md("## Step 3 · Three nodes, two edges"),
    sh("""SHAPE='(.config.stages[] | "\\(.name)\\t\\(.plugin.type)\\t\\(.plugin.name)"),
       (.config.connections[] | "\\(.from)\\t->\\t\\(.to)")'

jq -r "$SHAPE" "$WORK/pipelines/01-baseline.json" | column -t -s $'\\t'"""),

    md("## Step 4 · Deploy and run · run A"),
    sh('python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-01-baseline \\\n'
       '  --file "$WORK/pipelines/01-baseline.json"'),
    sh('RUN_A=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline)\n'
       'echo "$RUN_A"'),
    sh('gcloud dataproc clusters list --project "$PROJECT" --region us-central1 \\\n'
       '  --format="table(clusterName,status.state,config.masterConfig.machineTypeUri.basename(),'
       'config.workerConfig.numInstances,config.workerConfig.machineTypeUri.basename())"'),

    md("## Step 5 · What one run provisions, and what it costs"),
    sh('python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN_A"'),

    md("## Step 6 · The control number"),
    sh(f'{BQ} \\\n'
       '  "SELECT COUNT(*) AS rows_loaded, ROUND(SUM(amount), 2) AS total_amount,\n'
       '          COUNTIF(txn_ts IS NULL) AS null_ts\n'
       '   FROM \\`$FQ\\`"'),

    md("## Step 7 · The malformed day arrives · run B"),
    sh('gcloud storage cp "$WORK/sample/pos-2026-09-24-dirty.csv" \\\n'
       '  "gs://$BUCKET/raw/pos/pos-2026-09-24.csv"'),
    sh('tail -3 "$WORK/sample/pos-2026-09-24-dirty.csv"'),
    sh('RUN_B=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline)\n'
       'echo "$RUN_B"'),

    md("## Step 8 · Retry, quarantine, halt"),
    sh('python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN_B"'),

    md("## Step 9 · One query, two defects"),
    sh(f'{BQ} \\\n  "SELECT COUNT(*) AS rows_loaded FROM \\`$FQ\\`"'),
    sh('python3 cdap.py stages --endpoint "$ENDPOINT" --app pos-01-baseline \\\n'
       '  --run "$RUN_B" --stage Wrangler'),
    sh(f'{BQ} \\\n'
       '  "SELECT txn_id, txn_ts, qty, amount FROM \\`$FQ\\`\n'
       "   WHERE txn_id IN ('T-0900001','T-0900002','T-0900003') ORDER BY txn_id\""),

    md("## Step 10 · The fix is two properties · run C"),
    sh('diff <(jq -r "$SHAPE" "$WORK/pipelines/01-baseline.json") \\\n'
       '     <(jq -r "$SHAPE" "$WORK/pipelines/02-quarantine.json") \\\n'
       "  | grep '^>' | column -t -s $'\\t'"),
    sh('echo "gs://$BUCKET/quarantine/pos"'),
    sh('bq --project_id="${PROJECT:?}" rm -f -t "${DATASET:?}.sales_validated"\n'
       'python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-02-quarantine \\\n'
       '  --file "$WORK/pipelines/02-quarantine.json"'),
    sh('RUN_C=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine)\n'
       'echo "$RUN_C"'),

    md("## Step 11 · Field-level lineage, then the count that reconciles"),
    sh('python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN_C"'),
    sh(f'{BQ} \\\n  "SELECT COUNT(*) AS rows_loaded FROM \\`$FQ\\`"'),
    sh('gcloud storage cat "gs://$BUCKET/quarantine/pos/**" | head -4'),

    md("## Step 12 · Change nothing, run it again · run D"),
    sh('RUN_D=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine)\n'
       'echo "$RUN_D"'),
    sh('python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN_D"'),
    sh(f'{BQ} \\\n'
       '  "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \\`$FQ\\`"'),
    sh('python3 cdap.py logs --endpoint "$ENDPOINT" --app pos-02-quarantine \\\n'
       '  --run "$RUN_D" --grep FileAlreadyExists --tail 1'),

    md("## Delete the instance"),
    sh('gcloud beta data-fusion instances delete "${INSTANCE:?}" \\\n'
       '  --project "${PROJECT:?}" --location us-central1 --quiet'),
    sh('gcloud beta data-fusion instances list --project "$PROJECT" --location us-central1'),

    md("---\n# Teardown"),
    sh('gcloud dataproc clusters list --project "$PROJECT" --region us-central1'),
    sh('gcloud storage rm -r "gs://${BUCKET:?}"\n'
       'bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"'),
    sh('gcloud storage ls --project "$PROJECT"\n'
       'gcloud storage buckets list --project "$PROJECT" \\\n'
       '  --filter="labels.cdf_instance=$INSTANCE" --format="value(name)"\n'
       'bq --project_id="$PROJECT" ls'),
])
