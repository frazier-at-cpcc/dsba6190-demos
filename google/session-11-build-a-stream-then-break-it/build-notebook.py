#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 11 demonstration.

    python3 build-notebook.py

    prep.ipynb   T minus 30: create the topics, launch three streaming jobs, verify
    demo.ipynb   the hour, steps 1 to 11, teardown included

Both run on the Bash kernel. Every command mirrors an in-class step of
capture.sh, and every fixed sleep in capture.sh is an until-loop here, so a
cell returns as soon as the output exists. The notebooks carry step headings
and commands only. What to say is in RUNBOOK.md and its PDF.
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-11"


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


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$TOPIC" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')

JOBS = ('gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active '
        '--filter="name~crown-.*-$SUFFIX"')
# Backticks are escaped because every query sits inside double quotes.
BASE = '\\`$PROJECT.$DATASET.sales_baseline\\`'
LATE = '\\`$PROJECT.$DATASET.sales_lateness\\`'
DEDUP = '\\`$PROJECT.$DATASET.sales_dedup\\`'
# The late sale's own window. capture.sh filtered on "older than 20 minutes",
# which in class would also catch the step 3 burst; this band holds only the
# minute the late sale was rung.
BAND = ("store_id = 'CLT-031' AND window_start BETWEEN TIMESTAMP_SUB(TIMESTAMP('$LATE_PUB'), INTERVAL 31 MINUTE)"
        " AND TIMESTAMP_SUB(TIMESTAMP('$LATE_PUB'), INTERVAL 29 MINUTE)")

# One scalar from BigQuery, for the until-loops. Empty or NULL reads as 0.
N = ('n () { bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache '
     '--format=csv "$1" | tail -1 | grep -E "^[0-9]+$" || echo 0; }')

notebook("prep", [
    md("# Session 11 · Before class"),
    md("## T minus 30 · Stage the topics and launch three jobs"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## Verify"),
    sh(JOBS + ' \\\n  --format="table(name,state,creationTime)"'),
    sh('bq --project_id="$PROJECT" show "$PROJECT:$DATASET.sales_baseline" | head -5'),
    sh('gcloud pubsub subscriptions list --project "$PROJECT" --filter="name~$SUFFIX" --format="value(name)"'),
])

notebook("demo", [
    md("# Session 11 · Build a stream, then break it\n\n"
       "Crown Street Markets, a fictional 40-store Charlotte grocery chain, "
       "streams every register sale into BigQuery for the store managers' staffing dashboard."),
    LOAD,
    sh(N),

    md("## Step 1 · The substrate, in ninety seconds"),
    sh('gcloud pubsub topics create "$SCRATCH" --project "$PROJECT"\n'
       'gcloud pubsub subscriptions create "$SCRATCH" --topic "$SCRATCH" --project "$PROJECT"'),
    sh('for i in 1 2 3; do gcloud pubsub topics publish "$SCRATCH" --project "$PROJECT" '
       '--message "register test $i" --attribute store_id=CLT-00$i; done'),
    sh('gcloud pubsub subscriptions pull "$SCRATCH" --project "$PROJECT" --auto-ack --limit 3 \\\n'
       '  --format="table(message.data.decode(base64),message.attributes.store_id,message.messageId)"'),

    md("## Step 2 · Three jobs, started before class"),
    sh(JOBS + ' \\\n  --format="table(name,state,creationTime)"'),
    sh('for v in baseline lateness dedup; do\n'
       '  ID=$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active '
       '--filter="name=crown-$v-$SUFFIX" --format="value(id)")\n'
       '  echo "https://console.cloud.google.com/dataflow/jobs/$REGION/$ID?project=$PROJECT"\n'
       'done'),

    md("## Step 3 · A burst, and rows in BigQuery"),
    sh('BURST_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)\n'
       '(cd pipeline && $PY registers.py "$T/$TOPIC" burst 200)'),
    sh('until [ "$(n "SELECT SUM(sales) FROM ' + BASE + " WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)\")\" -ge 200 ] \\\n"
       '   && [ "$(n "SELECT SUM(sales) FROM ' + DEDUP + " WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)\")\" -ge 200 ]; do\n"
       '  sleep 15\ndone\n'
       "q \"SELECT 'baseline' job, SUM(sales) sales, ROUND(SUM(revenue),2) revenue, COUNT(DISTINCT window_start) windows FROM " + BASE + " WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)\n"
       "   UNION ALL SELECT 'dedup', SUM(sales), ROUND(SUM(revenue),2), COUNT(DISTINCT window_start) FROM " + DEDUP + " WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE)\""),
    sh('q "SELECT window_start, store_id, sales, revenue, pane FROM ' + BASE + "\n"
       "   WHERE window_start >= TIMESTAMP_TRUNC('$BURST_AT', MINUTE) ORDER BY sales DESC, store_id LIMIT 5\""),

    md("## Step 4 · The watermark, in the console, from the step 2 links"),

    md("## Step 5 · A sale from 30 minutes ago"),
    sh('LATE_PUB=$(date -u +%Y-%m-%dT%H:%M:%SZ)\n'
       '(cd pipeline && $PY registers.py "$T/$TOPIC" late)'),
    sh('until [ "$(n "SELECT COUNT(*) FROM ' + LATE + ' WHERE ' + BAND + '")" -ge 1 ]; do\n'
       '  sleep 15\ndone\n'
       'q "SELECT window_start, store_id, sales, revenue, pane FROM ' + BASE + '\n'
       '   WHERE ' + BAND + ' ORDER BY window_start"\n'
       'echo "baseline rows above: none means the late sale was dropped"'),

    md("## Step 6 · The allowed-lateness job re-fires the window"),
    sh('q "SELECT window_start, store_id, sales, revenue, pane FROM ' + LATE + '\n'
       '   WHERE ' + BAND + ' ORDER BY window_start"'),

    md("## Step 7 · One sale, published twice"),
    sh('DUP_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)\n'
       '(cd pipeline && $PY registers.py "$T/$TOPIC" duplicate)'),
    sh('until [ "$(n "SELECT SUM(sales) FROM ' + BASE + " WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)\")\" -ge 2 ] \\\n"
       '   && [ "$(n "SELECT SUM(sales) FROM ' + DEDUP + " WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)\")\" -ge 1 ]; do\n"
       '  sleep 15\ndone\n'
       "q \"SELECT 'baseline' job, SUM(sales) sales, ROUND(SUM(revenue),2) revenue FROM " + BASE + " WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)\n"
       "   UNION ALL SELECT 'dedup', SUM(sales), ROUND(SUM(revenue),2) FROM " + DEDUP + " WHERE store_id='CLT-007' AND window_start >= TIMESTAMP_TRUNC('$DUP_AT', MINUTE)\""),

    md("## Step 8 · A malformed record"),
    sh('(cd pipeline && $PY registers.py "$T/$TOPIC" malformed)'),
    sh('until OUT=$(gcloud pubsub subscriptions pull "dlq-$SUFFIX" --project "$PROJECT" --auto-ack --limit 5 \\\n'
       '        --format="yaml(message.data.decode(base64),message.attributes.error,message.attributes.sale_id)") \\\n'
       '      && [ -n "$OUT" ]; do\n'
       '  sleep 15\ndone\n'
       'echo "$OUT"'),
    sh('gcloud pubsub subscriptions pull "dlq-$SUFFIX" --project "$PROJECT" --auto-ack --limit 5 \\\n'
       '  --format="yaml(message.data.decode(base64),message.attributes.error,message.attributes.sale_id)"'),

    md("## Step 9 · Lag, backlog, and three jobs still running"),
    sh(JOBS + ' \\\n  --format="table(name,state)"'),

    md("## Step 10 · Drain one, cancel another"),
    sh('BID=$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active '
       '--filter="name=crown-baseline-$SUFFIX" --format="value(id)")\n'
       'LID=$(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active '
       '--filter="name=crown-lateness-$SUFFIX" --format="value(id)")\n'
       'echo "baseline $BID"; echo "lateness $LID"'),
    sh('gcloud dataflow jobs drain "${BID:?}" --project "$PROJECT" --region "$REGION"\n'
       'gcloud dataflow jobs cancel "${LID:?}" --project "$PROJECT" --region "$REGION"'),
    sh('until gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" '
       '--filter="name=crown-baseline-$SUFFIX AND state=Drained" --format="value(id)" 2>/dev/null | grep -q .; do\n'
       '  sleep 15\ndone\n'
       'gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --filter="name~crown-.*-$SUFFIX" \\\n'
       '  --format="table(name,state)"'),

    md("## Step 11 · Teardown"),
    sh('for j in $(gcloud dataflow jobs list --project "$PROJECT" --region "$REGION" --status=active '
       '--filter="name~crown-.*-$SUFFIX" --format="value(id)"); do\n'
       '  gcloud dataflow jobs cancel "${j:?}" --project "$PROJECT" --region "$REGION"\n'
       'done'),
    sh('for s in baseline lateness dedup dlq; do gcloud pubsub subscriptions delete "$s-${SUFFIX:?}" --project "$PROJECT" --quiet; done\n'
       'gcloud pubsub subscriptions delete "${SCRATCH:?}" --project "$PROJECT" --quiet\n'
       'gcloud pubsub topics delete "${TOPIC:?}" "${DLQ:?}" "${SCRATCH:?}" --project "$PROJECT" --quiet'),
    sh('bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"\n'
       'gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT" 2>&1 | tail -1'),
    sh(JOBS + '\n'
       'gcloud pubsub topics list --project "$PROJECT" --filter="name~$SUFFIX"'),
])
