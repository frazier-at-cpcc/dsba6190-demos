#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 14 demonstration.

    python3 build-notebook.py

    prep.ipynb   generate the store-sales files, create the bucket, backfill the table
    demo.ipynb   steps 1 to 8, teardown included

Commands only, on the Bash kernel. The walkthrough is in RUNBOOK.md.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-14"


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


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$DATASET" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
T = "\\`$DS.store_sales\\`"
GOOD = '"gs://$BUCKET/raw/dt=$LAST_NIGHT/sales.csv"'
DASH = ("SELECT COUNT(*) AS store_days, ROUND(SUM(sales)) AS sales_usd FROM (\n"
        "     SELECT sale_date, store_id, region, COUNT(DISTINCT basket_id) AS baskets,\n"
        "            SUM(items) AS items, SUM(basket_value) AS sales\n"
        f"     FROM {T}\n"
        "     WHERE {filter}\n"
        "     GROUP BY 1, 2, 3)")
JOBS = "\\`region-us\\`.INFORMATION_SCHEMA.JOBS"
MINE = "EXISTS (SELECT 1 FROM UNNEST(j.labels) AS r WHERE r.key = 'run' AND r.value = '$SUFFIX')"

notebook("prep", [
    md("# Session 14 · Before you start"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    sh(f'q "SELECT COUNT(*) AS \\`rows\\`, COUNT(DISTINCT sale_date) AS nights, MAX(sale_date) AS newest FROM {T}"'),
])

notebook("demo", [
    md("# Session 14 · Green status, wrong data\n\n"
       "Crown Street Markets, a fictional 40-store Charlotte grocery chain, loads last night's register "
       "baskets into BigQuery every night. The replenishment dashboard reads them at 06:00."),
    LOAD,

    md("## Step 1 · The nightly load succeeds"),
    sh('bq --project_id="$PROJECT" --format=json show "$PROJECT:$DATASET.store_sales" \\\n'
       "  | jq '{labels, timePartitioning, numRows}'"),
    sh(f"nightly_load {GOOD}"),
    sh(f'q "SELECT sale_date, COUNT(*) AS \\`rows\\`, ROUND(SUM(basket_value)) AS sales_usd FROM {T}\n'
       "   WHERE sale_date >= DATE_SUB('$LAST_NIGHT', INTERVAL 3 DAY) GROUP BY 1 ORDER BY 1\""),

    md("## Step 2 · Four checks in SQL"),
    sh("cat sql/checks.sql"),
    sh("checks"),

    md("## Step 3 · Break it three ways, and every load succeeds"),
    sh('nightly_load "gs://$BUCKET/incoming/one-store.csv"'),
    sh("checks"),
    sh('nightly_load "gs://$BUCKET/incoming/renamed-column.csv"'),
    sh("checks"),
    sh(f"nightly_load {GOOD}\n"
       f'PIPELINE=fix q "ALTER TABLE {T} DROP COLUMN basket_total"'),
    sh('nightly_load "gs://$BUCKET/incoming/north-nulls.csv"'),
    sh("checks"),
    sh(f'q "SELECT region, COUNT(*) AS \\`rows\\`, COUNTIF(basket_value IS NULL) AS null_values,\n'
       "          ROUND(AVG(basket_value), 2) AS mean_basket\n"
       f"   FROM {T} WHERE sale_date = '$LAST_NIGHT' GROUP BY 1 ORDER BY 1\""),
    sh(f"nightly_load {GOOD}\nchecks"),

    md("## Step 4 · Make one check a symptom alert"),
    sh("log_checks"),
    sh("cat metric.yaml\n"
       'gcloud logging metrics create "$METRIC" --config-from-file=metric.yaml --project "$PROJECT"'),
    sh('CHANNEL=$(gcloud beta monitoring channels create --project "$PROJECT" \\\n'
       "    --display-name=\"Replenishment on-call (run $SUFFIX)\" --type=email \\\n"
       "    --channel-labels=email_address=instructor@example.edu --format='value(name)')\n"
       'echo "$CHANNEL" | tee channel.name'),
    sh('until POLICY=$(gcloud monitoring policies create --project "$PROJECT" --policy-from-file=policy.json \\\n'
       "        --notification-channels=\"$CHANNEL\" --format='value(name)' 2>/dev/null); do\n"
       "  echo 'The new metric is not visible to Monitoring yet. Retrying in 30 s.'; sleep 30\n"
       "done\n"
       'echo "$POLICY" | tee policy.name'),
    sh('gcloud monitoring policies describe "$POLICY" --project "$PROJECT" \\\n'
       '  --format="yaml(displayName,enabled,conditions[0].conditionThreshold.filter,'
       'conditions[0].conditionThreshold.comparison,conditions[0].conditionThreshold.thresholdValue,'
       'notificationChannels.len())"'),
    sh('nightly_load "gs://$BUCKET/incoming/one-store.csv" >/dev/null && log_checks'),
    sh("sleep 10\ngcloud logging read \"logName=\\\"projects/$PROJECT/logs/$LOG\\\" AND jsonPayload.status=\\\"RED\\\"\" \\\n"
       '  --project "$PROJECT" --limit=1 --format=json | jq \'.[0] | {severity, logName, jsonPayload}\''),
    sh(f"nightly_load {GOOD} >/dev/null && checks"),

    md("## Step 5 · The SLO and the error budget"),
    sh('q "SELECT sale_date, state, finished_at, rows_loaded, corrected_at FROM \\`$DS.load_runs\\`\n'
       "   WHERE TIME(finished_at) > '06:00:00' OR corrected_at IS NOT NULL ORDER BY 1\""),
    sh('PIPELINE=slo_report q "$(sed "s/@@DS@@/$DS/g" sql/error-budget.sql)"'),
    sh("red_count"),

    md("## Step 6 · Delete by mistake, restore with time travel"),
    sh('BEFORE=$(date -u +%FT%TZ); echo "recovery point $BEFORE"; sleep 2\n'
       f'PIPELINE=mistake q "DELETE FROM {T}\n'
       "   WHERE sale_date = '$LAST_NIGHT'\n"
       "   -- AND register_id = 'CLT-040-R99'   the line that was meant to be here\""),
    sh("checks"),
    sh('PIPELINE=restore q "CREATE TEMP TABLE lost AS\n'
       f"   SELECT * FROM {T} FOR SYSTEM_TIME AS OF TIMESTAMP '${{BEFORE:?}}' WHERE sale_date = '$LAST_NIGHT';\n"
       f'   INSERT INTO {T} SELECT * FROM lost;"'),
    sh("checks"),
    sh('q "WITH ours AS (\n'
       "     SELECT job_id, l.value AS step, start_time, end_time\n"
       f"     FROM {JOBS} AS j, UNNEST(j.labels) AS l\n"
       "     WHERE l.key = 'pipeline' AND l.value IN ('mistake', 'restore') AND j.parent_job_id IS NULL AND " + MINE + "\n"
       "       AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR))\n"
       "   SELECT o.step, FORMAT_TIMESTAMP('%T', o.end_time) AS finished_utc,\n"
       "          SUM(IF(j.statement_type = 'DELETE', j.dml_statistics.deleted_row_count, 0)) AS deleted,\n"
       "          SUM(IF(j.statement_type = 'INSERT', j.dml_statistics.inserted_row_count, 0)) AS inserted,\n"
              "          TIMESTAMP_DIFF(o.end_time, MIN(o.end_time) OVER (), SECOND) AS s_after_mistake\n"
       "   FROM ours AS o\n"
       f"   JOIN {JOBS} AS j ON (j.job_id = o.job_id OR j.parent_job_id = o.job_id)\n"
       "    AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)\n"
       '   GROUP BY o.step, o.start_time, o.end_time ORDER BY o.end_time"'),
    sh('bq --project_id="$PROJECT" --location=US mk --dataset --label team:replenishment "$PROJECT:$BACKUP"\n'
       'PIPELINE=backup q "CREATE SNAPSHOT TABLE \\`$PROJECT.$BACKUP.store_sales_$LAST_ID\\`\n'
       f"   CLONE {T}\n"
       '   OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))"\n'
       'bq --project_id="$PROJECT" ls "$PROJECT:$BACKUP"'),

    md("## Step 7 · FinOps: labels, the cheapest fix, and a storage move nobody notices"),
    sh('PIPELINE=replenishment_dashboard q "' +
       DASH.format(filter="DATE_DIFF(CURRENT_DATE('America/New_York'), sale_date, DAY) BETWEEN 1 AND 7") + '"'),
    sh('PIPELINE=replenishment_dashboard q "' +
       DASH.format(filter="sale_date BETWEEN DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 7 DAY)\n"
                          "                         AND DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY)") + '"'),
    sh('q "SELECT l.value AS pipeline, COUNT(*) AS jobs,\n'
       "          ROUND(SUM(total_bytes_processed) / POW(2, 20), 1) AS processed_mb,\n"
       "          ROUND(SUM(IFNULL(total_bytes_billed, 0)) / POW(2, 20), 1) AS billed_mb\n"
       f"   FROM {JOBS} AS j, UNNEST(j.labels) AS l\n"
       "   WHERE l.key = 'pipeline' AND j.parent_job_id IS NULL AND " + MINE + "\n"
       "     AND j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)\n"
       '   GROUP BY 1 ORDER BY billed_mb DESC, jobs DESC"'),
    sh('gcloud storage buckets update "gs://$BUCKET" --project "$PROJECT" --lifecycle-file=lifecycle.json\n'
       'gcloud storage buckets describe "gs://$BUCKET" --project "$PROJECT" \\\n'
       "  --format='yaml(default_storage_class,labels,lifecycle_config)'"),
    sh('OLD="gs://$BUCKET/raw/dt=$FIRST_NIGHT/sales.csv"\n'
       "gcloud storage objects describe \"$OLD\" --project \"$PROJECT\" --format=json \\\n  | jq -r '\"gs://\\(.bucket)/\\(.name)  \\(.storage_class)  generation \\(.generation)\"'\n"
       'gcloud storage objects update "$OLD" --project "$PROJECT" --storage-class=NEARLINE\n'
       "gcloud storage objects describe \"$OLD\" --project \"$PROJECT\" --format=json \\\n  | jq -r '\"gs://\\(.bucket)/\\(.name)  \\(.storage_class)  generation \\(.generation)\"'"),
    sh('gcloud storage cat "$OLD" --project "$PROJECT" | sed -n 1,3p'),

    md("## Step 8 · Teardown, and verify nothing is left"),
    sh('POLICY=${POLICY:-$(cat policy.name)}; CHANNEL=${CHANNEL:-$(cat channel.name)}\n'
       'gcloud monitoring policies delete "${POLICY:?}" --project "$PROJECT" --quiet\n'
       'gcloud beta monitoring channels delete "${CHANNEL:?}" --project "$PROJECT" --quiet'),
    sh('gcloud logging metrics delete "${METRIC:?}" --project "$PROJECT" --quiet\n'
       'gcloud logging logs delete "${LOG:?}" --project "$PROJECT" --quiet'),
    sh('gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT" 2>&1 | tail -2'),
    sh('bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"\n'
       'bq --project_id="$PROJECT" rm -r -f -d "${BACKUP:?}"'),
    sh("printf '%-12s %s\\n' datasets  $(bq --project_id=\"$PROJECT\" ls --max_results=1000 | grep -c \"$SUFFIX\")\n"
       "printf '%-12s %s\\n' snapshots $(bq --project_id=\"$PROJECT\" ls \"$PROJECT:$BACKUP\" 2>/dev/null | grep -c SNAPSHOT)\n"
       "printf '%-12s %s\\n' buckets   $(gcloud storage ls --project \"$PROJECT\" | grep -c \"$SUFFIX\")\n"
       "printf '%-12s %s\\n' metrics   $(gcloud logging metrics list --project \"$PROJECT\" --format='value(name)' | grep -c \"$SUFFIX\")\n"
       "printf '%-12s %s\\n' logs      $(gcloud logging logs list --project \"$PROJECT\" | grep -c \"$SUFFIX\")\n"
       "printf '%-12s %s\\n' policies  $(gcloud monitoring policies list --project \"$PROJECT\" --format='value(displayName)' | grep -c \"$SUFFIX\")\n"
       "printf '%-12s %s\\n' channels  $(gcloud beta monitoring channels list --project \"$PROJECT\" --format='value(displayName)' | grep -c \"$SUFFIX\")"),
])
