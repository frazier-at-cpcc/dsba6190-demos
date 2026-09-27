#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 7 demonstration.

    python3 build-notebook.py

    prep.ipynb   T minus 45 to T minus 35: provision, verify, re-check the figures
    demo.ipynb   the hour, steps 1 to 12, teardown included

Both run on the Bash kernel, so every cell is the command exactly as it would
be typed in a terminal and shell variables persist between cells. The
notebooks carry step headings and commands only. What to say is in
RUNBOOK.md and its PDF. Regenerate after editing the runbook.
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-07"


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


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$DS   $BUCKET   $ANALYST" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
COLS = """vendor_id, pickup_datetime, dropoff_datetime, passenger_count, trip_distance,
          payment_type, fare_amount, tip_amount, total_amount,
          pickup_location_id, dropoff_location_id"""
YEAR = "pickup_datetime >= '2022-01-01' AND pickup_datetime < '2023-01-01'"
WEEK = """WHERE pickup_datetime >= '2022-07-04' AND pickup_datetime < '2022-07-11'
       AND pickup_location_id = '132'
     GROUP BY 1"""
WEEKLY = "SELECT pickup_location_id, COUNT(*) AS trips, ROUND(SUM(total_amount), 2) AS revenue"
BYPAY = """SELECT payment_type, COUNT(*) AS trips, ROUND(AVG(tip_amount), 2) AS avg_tip
     FROM \\`$DS.trips_ext\\` GROUP BY 1 ORDER BY trips DESC"""
LAKE = "gs://$BUCKET/trips/2022-01/*.parquet"
COUNT = """SELECT COUNT(*) AS trips, COUNT(DISTINCT vendor_id) AS vendors,
          STRING_AGG(DISTINCT vendor_id ORDER BY vendor_id) AS vendor_ids
   FROM \\`$DS.trips_lake\\`"""

notebook("prep", [
    md("# Session 7 · Before class"),
    md("## T minus 45 · Provision"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## T minus 38 · Verify"),
    sh('as_analyst q "SELECT SESSION_USER() AS who"'),
    sh('bq --project_id="$PROJECT" --location=US show --connection "$CONNECTION" | head -3'),
    sh('gcloud storage ls "gs://$BUCKET/trips/2022-01/"'),
    md("## T minus 35 · Re-verify the published figures"),
])

notebook("demo", [
    md("# Session 7 · Make the cost visible, then govern it\n\n"
       "Queen City Trip Analytics, a fictional South End, Charlotte company, "
       "prices its dashboards and governs what its first fleet customer can see."),
    LOAD,

    md("## Step 1 · The estimator prices a query before it runs"),
    sh('bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false --dry_run \\\n'
       '  "SELECT pickup_datetime, passenger_count, fare_amount FROM \\`$TAXI\\`"'),
    sh('bq --project_id="$PROJECT" show --format=json "${TAXI/./:}" | jq -M \'{numRows, numBytes}\''),

    md("## Step 2 · `SELECT *`"),
    sh('dry "SELECT * FROM \\`$TAXI\\`"'),

    md("## Step 3 · Three named columns"),
    sh('dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \\`$TAXI\\`"'),
    sh('dry "SELECT AVG(fare_amount) FROM \\`$TAXI\\`"'),

    md("## Step 4 · `LIMIT 10`"),
    sh('dry "SELECT * FROM \\`$TAXI\\` LIMIT 10"'),

    md("## Step 5 · `COUNT(*)`"),
    sh('dry "SELECT COUNT(*) FROM \\`$TAXI\\`"'),
    sh('q "SELECT COUNT(*) AS trips FROM \\`$TAXI\\`"'),

    md("## Step 6 · Two filters, identical rows"),
    sh('dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \\`$WILD\\`\n'
       "     WHERE _TABLE_SUFFIX = '2022'\""),
    sh('dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \\`$WILD\\`\n'
       '     WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022"'),

    md("## Step 7 · Partition and cluster, built live"),
    sh(f'q "CREATE TABLE \\`$DS.trips_2022\\` AS\n'
       f'   SELECT {COLS}\n'
       f'   FROM \\`$TAXI\\` WHERE {YEAR}"'),
    sh(f'q "CREATE TABLE \\`$DS.trips_2022_part\\`\n'
       f'   PARTITION BY DATE(pickup_datetime) CLUSTER BY pickup_location_id AS\n'
       f'   SELECT {COLS}\n'
       f'   FROM \\`$TAXI\\` WHERE {YEAR}"'),
    sh('for t in trips_2022 trips_2022_part; do\n'
       '  bq --project_id="$PROJECT" show --format=json "$PROJECT:$DATASET.$t" \\\n'
       "    | jq -cM '{table: .tableReference.tableId, numRows, numBytes,\n"
       "             partitioning: .timePartitioning.type, clustering: .clustering.fields}'\n"
       'done'),
    sh(f'dry "{WEEKLY}\n     FROM \\`$DS.trips_2022\\`\n     {WEEK}"'),
    sh(f'dry "{WEEKLY}\n     FROM \\`$DS.trips_2022_part\\`\n     {WEEK}"'),
    sh(f'q "{WEEKLY}\n   FROM \\`$DS.trips_2022\\`\n   {WEEK}"'),
    sh(f'q "{WEEKLY}\n   FROM \\`$DS.trips_2022_part\\`\n   {WEEK}"'),
    sh('q "ALTER TABLE \\`$DS.trips_2022_part\\` SET OPTIONS (require_partition_filter = TRUE)"'),
    sh("q \"SELECT COUNT(*) AS trips FROM \\`$DS.trips_2022_part\\` WHERE pickup_location_id = '132'\""),

    md("## Step 8 · The execution plan"),
    sh('q "SELECT pickup_location_id, COUNT(*) AS trips FROM \\`$DS.trips_2022\\`\n'
       '   GROUP BY 1 ORDER BY trips DESC LIMIT 5"'),
    sh("plan"),

    md("## Step 9 · An external table over Parquet"),
    sh('gcloud storage ls -l "gs://$BUCKET/trips/2022-01/"'),
    sh(f'q "CREATE EXTERNAL TABLE \\`$DS.trips_ext\\`\n'
       f"   OPTIONS (format = 'PARQUET', uris = ['{LAKE}'])\""),
    sh('for t in trips_ext trips_2022; do\n'
       '  bq --project_id="$PROJECT" show --format=json "$PROJECT:$DATASET.$t" \\\n'
       "    | jq -cM '{table: .tableReference.tableId, type, numRows, numBytes}'\n"
       'done'),
    sh(f'dry "{BYPAY}"'),
    sh(f'q "{BYPAY}"'),

    md("## Step 10 · BigLake, delegation, and a policy tag"),
    sh(f'q "CREATE EXTERNAL TABLE \\`$DS.trips_lake\\`\n'
       f'   WITH CONNECTION \\`$CONNECTION\\`\n'
       f"   OPTIONS (format = 'PARQUET', uris = ['{LAKE}'])\""),
    sh('as_analyst q "SELECT COUNT(*) AS trips FROM \\`$DS.trips_ext\\`"'),
    sh('as_analyst q "SELECT COUNT(*) AS trips FROM \\`$DS.trips_lake\\`"'),
    sh('bq --project_id="$PROJECT" show --schema --format=json "$PROJECT:$DATASET.trips_lake" \\\n'
       '  | jq --arg tag "$POLICY_TAG" \\\n'
       "       'map(if .name == \"pickup_location_id\" or .name == \"dropoff_location_id\"\n"
       "            then . + {policyTags: {names: [$tag]}} else . end)' \\\n"
       '  > "$WORK/schema-tagged.json"\n'
       'bq --project_id="$PROJECT" update --schema "$WORK/schema-tagged.json" "$PROJECT:$DATASET.trips_lake"'),
    sh('as_analyst q "SELECT * FROM \\`$DS.trips_lake\\` LIMIT 3"'),
    sh('as_analyst q "SELECT * EXCEPT (pickup_location_id, dropoff_location_id)\n'
       '              FROM \\`$DS.trips_lake\\` ORDER BY pickup_datetime LIMIT 3"'),
    sh('q "SELECT pickup_location_id, COUNT(*) AS trips FROM \\`$DS.trips_lake\\`\n'
       '   GROUP BY 1 ORDER BY trips DESC LIMIT 3"'),

    md("## Step 11 · Row access policies"),
    sh('q "CREATE ROW ACCESS POLICY vendor_2 ON \\`$DS.trips_lake\\`\n'
       "   GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')\""),
    sh(f'q "{COUNT}"'),
    sh('q "CREATE ROW ACCESS POLICY all_rows ON \\`$DS.trips_lake\\`\n'
       "   GRANT TO ('user:$ME') FILTER USING (TRUE)\""),
    sh(f'q "{COUNT}"'),
    sh(f'as_analyst q "{COUNT}"'),
    sh('q "CREATE ROW ACCESS POLICY vendor_2 ON \\`$DS.trips_ext\\`\n'
       "   GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')\""),
    sh('bq --project_id="$PROJECT" ls --row_access_policies "$PROJECT:$DATASET.trips_lake"'),

    md("## Step 12 · Teardown"),
    sh('bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"\n'
       'bq --project_id="${PROJECT:?}" --location=US rm -f --connection "${CONNECTION:?}"\n'
       'curl -s -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token)" \\\n'
       '     -H "x-goog-user-project: ${PROJECT:?}" "https://datacatalog.googleapis.com/v1/${TAXONOMY:?}"\n'
       'gcloud storage rm -r "gs://${BUCKET:?}"'),
    sh('bq --project_id="$PROJECT" ls | grep -c "$DATASET"\n'
       'bq --project_id="$PROJECT" --location=US ls --connection | grep -c "$CONNECTION_ID"\n'
       'gcloud data-catalog taxonomies list --location us --project "$PROJECT" --format="value(name)" | grep -c .\n'
       'gcloud storage ls --project "$PROJECT" | grep -c "$BUCKET"'),
])
