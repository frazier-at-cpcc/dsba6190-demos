#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 10 demonstration.

    python3 build-notebook.py

    prep.ipynb   about five minutes ahead: bucket, the generate batch, the BigQuery load, verify
    demo.ipynb   the demonstration, steps 1 to 11, teardown included

Both run on the Bash kernel. Each Spark variant takes about three minutes
from submission to finish, so demo.ipynb submits it with --async one step
before it is needed and collects it with an until-loop (`waitfor`). At most
one batch runs at a time. The notebooks carry step headings and commands
only. The walkthrough is in RUNBOOK.md.

After writing, the script validates both notebooks: the JSON parses, every
code cell passes `bash -n`, and every line that deletes names its target
through a ${VAR:?} guard.
"""

import json
import pathlib
import re
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-10"


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
    print(f"wrote {name}.ipynb: {len(cells)} cells, "
          f"{sum(c['cell_type'] == 'code' for c in cells)} commands")


def md(text):
    return ("markdown", text)


def sh(text):
    return ("code", text)


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$BUCKET" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
T = "\\`$DS.trips\\`"
A = "\\`$DS.accounts\\`"

notebook("prep", [
    md("# Session 10 · Before you start"),
    md("## Provision and generate, about five minutes ahead"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## Verify"),
    sh('gcloud storage du -s "$BASE/data/trips" "$BASE/data/accounts"'),
    sh(f'bqq "SELECT COUNT(*) AS trips FROM {T}"'),
    sh('gcloud dataproc batches list --region "$REGION" --filter="state=RUNNING"'),
])

notebook("demo", [
    md("# Session 10 · Read a plan, find the skew\n\n"
       "Queen City Trip Analytics, a fictional South End, Charlotte analytics firm, "
       "bills its fleet customers every month by joining a year of trips to its accounts."),
    LOAD,

    md("## Step 1 · The billing job, and the first batch submitted"),
    sh('submit baseline baseline "$OFF"'),
    sh('gcloud storage du -s "$BASE/data/trips" "$BASE/data/accounts"'),
    sh("gcloud storage cat \"$BASE/jobs/billing.py\" | sed -n '/^trips = spark.read/,/agg(F.count/p'"),

    md("## Step 2 · Read the plan"),
    sh("waitfor baseline"),
    sh("planof baseline | head -17"),
    sh("planof baseline | grep -A2 -E '^\\((4|9|14)\\) Exchange'"),
    sh('submit broadcast broadcast "$OFF"'),

    md("## Step 3 · The stage table, and the straggler"),
    sh('submit salted salted "$OFF"'),
    sh("evlog baseline"),
    sh("biggest baseline"),

    md("## Step 4 · The cause, in the data"),
    sh('submit aqe aqe "$AQE_ON"'),
    sh(f'bqq "SELECT account_id, COUNT(*) AS trips, ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share\n'
       f'     FROM {T} GROUP BY 1 ORDER BY 2 DESC LIMIT 5"'),

    md("## Step 5 · Broadcast: the shuffle is gone"),
    sh("waitfor broadcast"),
    sh("planof broadcast | sed -n '2,10p'"),
    sh("evlog broadcast"),

    md("## Step 6 · Salted: the straggler is split"),
    sh("waitfor salted"),
    sh("planof salted | grep -A2 -E '^\\((3|5|10)\\) (Project|Exchange|Generate)'"),
    sh("evlog salted"),
    sh("biggest salted"),

    md("## Step 7 · Adaptive query execution: coalesced, not split"),
    sh("waitfor aqe"),
    sh("planof aqe | grep -E '^AdaptiveSparkPlan|isFinalPlan'"),
    sh("finalplan aqe | grep -E 'AQEShuffleRead|SortMergeJoin'"),
    sh("evlog aqe"),
    sh("biggest aqe"),

    md("## Step 8 · The same join in BigQuery"),
    sh(f'bqq "SELECT a.tier, DATE_TRUNC(t.pickup_date, MONTH) AS month, COUNT(*) AS trips,\n'
       f'            ROUND(SUM(t.fare), 2) AS revenue\n'
       f'     FROM {T} t JOIN {A} a USING (account_id)\n'
       f'     GROUP BY 1, 2 ORDER BY 1, 2 LIMIT 6"'),

    md("## Step 9 · Four variants, one answer"),
    sh('for v in baseline broadcast salted aqe; do\n'
       '  bq --project_id="$PROJECT" --location=US load --source_format=PARQUET \\\n'
       '     --replace "$PROJECT:${DATASET:?}.out_$v" "$BASE/out/$v/*.parquet" >/dev/null\n'
       '  bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false --format=csv \\\n'
       "     \"SELECT '$v', COUNT(*), ROUND(SUM(revenue), 2) FROM \\`$DS.out_$v\\`\" | tail -1\n"
       'done'),

    sh("for v in baseline broadcast salted aqe; do printf '%-10s ' \"$v\"; apptime \"$v\"; done"),

    md("## Step 10 · Save and number the plan"),
    sh("planof baseline > skewed-plan.txt\n"
       "nl -ba -w2 -s '  ' skewed-plan.txt | sed -n '6,16p'"),

    md("## Step 11 · Teardown"),
    sh('gcloud storage rm -r "gs://${BUCKET:?}"'),
    sh('bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"'),
    sh('gcloud dataproc batches list --region "$REGION" --filter="state=RUNNING"\n'
       'gcloud storage ls | grep -c "${BUCKET:?}"; bq --project_id="$PROJECT" ls | grep -c "${DATASET:?}"'),
])


# Validation. Any failure raises, so a broken notebook never ships silently.
DESTRUCTIVE = re.compile(r"(\brm\b|\bdelete\b|--replace\b)")
for name in ("prep", "demo"):
    nb = json.loads((HERE / f"{name}.ipynb").read_text())
    code = [c for c in nb["cells"] if c["cell_type"] == "code"]
    for i, c in enumerate(code):
        src = "".join(c["source"])
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
            f.write(src + "\n")
        r = subprocess.run(["bash", "-n", f.name], capture_output=True, text=True)
        pathlib.Path(f.name).unlink()
        assert r.returncode == 0, f"{name} cell {i}: bash -n failed\n{src}\n{r.stderr}"
        for line in src.splitlines():
            if DESTRUCTIVE.search(line):
                assert ":?}" in line, f"{name} cell {i}: unguarded destructive line: {line}"
    headings = [c for c in nb["cells"] if c["cell_type"] == "markdown"
                and "".join(c["source"]).startswith("## Step ")]
    print(f"validated {name}.ipynb: JSON parses, {len(code)} cells pass bash -n, "
          f"destructive lines guarded, {len(headings)} step headings")
