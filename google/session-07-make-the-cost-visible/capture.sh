#!/usr/bin/env bash
# Capture the Session 7 live demo: make the cost visible, make governance visible.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages the estate with live-setup.sh into .work/, runs all twelve steps
# against the real project, writes every command's real output to capture/,
# and tears the estate down through an exit trap. Re-runnable: the suffix is
# derived per run.
#
# Cost of one run: about 10 GB of on-demand scan, most of it the two copies of
# 2022 built at step 7 and the Parquet export in live-setup.sh. Every figure
# in steps 1 to 6 is a dry run and costs nothing.
#
# It leaves one thing behind on purpose: the second principal,
# dsba6190-analyst, and its three grants. A service account is free, and
# recreating it costs five minutes of IAM propagation on the next run.
#
# DO NOT RUN THIS IN CLASS. It deletes the dataset, the connection, the
# taxonomy and the bucket when it exits. live-setup.sh is the one to run
# before class.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"
OUT="$HERE/capture"
export SUFFIX="$(date +%s | tail -c 6)"
mkdir -p "$OUT"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}

# The names live-setup.sh will derive from the same suffix, so the trap can
# clean up even if staging fails halfway.
DATASET="dsba6190_wh_$SUFFIX"; BUCKET="dsba6190-trips-$SUFFIX"
CONNECTION="$PROJECT.US.dsba6190-lake-$SUFFIX"; TAXONOMY=""

cleanup () {
  step "Cleanup"
  if [ -z "$TAXONOMY" ]; then
    TAXONOMY="$(gcloud data-catalog taxonomies list --location us --project "$PROJECT" \
                  --filter="displayName=dsba6190-$SUFFIX" --format="value(name)" 2>/dev/null || true)"
  fi
  bq --project_id="$PROJECT" rm -r -f -d "$DATASET" >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" --location=US rm -f --connection "$CONNECTION" >/dev/null 2>&1 || true
  gcloud storage rm -r "gs://$BUCKET" --project "$PROJECT" >/dev/null 2>&1 || true
  [ -n "$TAXONOMY" ] && curl -s -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token)" \
       -H "x-goog-user-project: $PROJECT" \
       "https://datacatalog.googleapis.com/v1/$TAXONOMY" >/dev/null 2>&1 || true
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"

WEEK="WHERE pickup_datetime >= '2022-07-04' AND pickup_datetime < '2022-07-11'
          AND pickup_location_id = '132'"
WEEKLY="SELECT pickup_location_id, COUNT(*) AS trips, ROUND(SUM(total_amount), 2) AS revenue"
COLS="vendor_id, pickup_datetime, dropoff_datetime, passenger_count, trip_distance,
      payment_type, fare_amount, tip_amount, total_amount, pickup_location_id, dropoff_location_id"

# ============================================================ the cost half
step "Step 1 · The estimator prices a query before it runs"
run "bq query --dry_run 'SELECT pickup_datetime, passenger_count, fare_amount FROM \`\$TAXI\`'" \
    01-dry-run-native.txt \
    bq --project_id="$PROJECT" --location=US --quiet query --use_legacy_sql=false --dry_run \
       "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$TAXI\`"
run "bq show --format=prettyjson \$TAXI   (numRows, numBytes)" 02-table-size.txt \
    bash -c "bq --project_id=$PROJECT show --format=json '${TAXI/./:}' \
             | jq '{numRows, numBytes, numLongTermBytes, location}'"

step "Step 2 · SELECT *"
run "dry \"SELECT * FROM \`\$TAXI\`\"" 03-select-star.txt dry "SELECT * FROM \`$TAXI\`"

step "Step 3 · Three named columns"
run "dry \"SELECT pickup_datetime, passenger_count, fare_amount FROM \`\$TAXI\`\"" \
    04-three-columns.txt dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$TAXI\`"
run "dry \"SELECT AVG(fare_amount) FROM \`\$TAXI\`\"" 05-one-column.txt \
    dry "SELECT AVG(fare_amount) FROM \`$TAXI\`"

step "Step 4 · LIMIT 10"
run "dry \"SELECT * FROM \`\$TAXI\` LIMIT 10\"" 06-limit-10.txt dry "SELECT * FROM \`$TAXI\` LIMIT 10"

step "Step 5 · COUNT(*)"
run "dry \"SELECT COUNT(*) FROM \`\$TAXI\`\"" 07-count-dry.txt dry "SELECT COUNT(*) FROM \`$TAXI\`"
run "q \"SELECT COUNT(*) AS trips FROM \`\$TAXI\`\"" 08-count-run.txt \
    q "SELECT COUNT(*) AS trips FROM \`$TAXI\`"

step "Step 6 · Two filters, identical rows"
run "dry \"... FROM \`\$WILD\` WHERE _TABLE_SUFFIX = '2022'\"" 09-wildcard-suffix.txt \
    dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$WILD\` WHERE _TABLE_SUFFIX = '2022'"
run "dry \"... FROM \`\$WILD\` WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022\"" \
    10-wildcard-column.txt \
    dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$WILD\` WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022"

step "Step 7 · Partition and cluster, live"
run "q \"CREATE TABLE \$DS.trips_2022 AS SELECT <11 columns> FROM \`\$TAXI\` WHERE <2022 only>\"" \
    11-ctas-plain.txt \
    q "CREATE TABLE \`$DS.trips_2022\` AS SELECT $COLS FROM \`$TAXI\`
       WHERE pickup_datetime >= '2022-01-01' AND pickup_datetime < '2023-01-01'"
run "q \"CREATE TABLE \$DS.trips_2022_part PARTITION BY DATE(pickup_datetime) CLUSTER BY pickup_location_id AS ...\"" \
    12-ctas-partitioned.txt \
    q "CREATE TABLE \`$DS.trips_2022_part\`
       PARTITION BY DATE(pickup_datetime) CLUSTER BY pickup_location_id AS
       SELECT $COLS FROM \`$TAXI\`
       WHERE pickup_datetime >= '2022-01-01' AND pickup_datetime < '2023-01-01'"
run "bq show   (both copies: rows, bytes, partitioning, clustering)" 13-two-copies.txt \
    bash -c "for t in trips_2022 trips_2022_part; do
               bq --project_id=$PROJECT show --format=json $PROJECT:$DATASET.\$t \
               | jq -c '{table: .tableReference.tableId, numRows, numBytes,
                         partitioning: .timePartitioning.type, clustering: .clustering.fields}'
             done"
run "dry \"$WEEKLY FROM trips_2022 <one week, JFK>\"" 14-week-plain-dry.txt \
    dry "$WEEKLY FROM \`$DS.trips_2022\` $WEEK GROUP BY 1"
run "dry \"$WEEKLY FROM trips_2022_part <one week, JFK>\"" 15-week-part-dry.txt \
    dry "$WEEKLY FROM \`$DS.trips_2022_part\` $WEEK GROUP BY 1"
run "q \"$WEEKLY FROM trips_2022 <one week, JFK>\"" 16-week-plain-run.txt \
    q "$WEEKLY FROM \`$DS.trips_2022\` $WEEK GROUP BY 1"
run "q \"$WEEKLY FROM trips_2022_part <one week, JFK>\"" 17-week-part-run.txt \
    q "$WEEKLY FROM \`$DS.trips_2022_part\` $WEEK GROUP BY 1"
run "q \"ALTER TABLE trips_2022_part SET OPTIONS (require_partition_filter = TRUE)\"" \
    18-require-filter.txt \
    q "ALTER TABLE \`$DS.trips_2022_part\` SET OPTIONS (require_partition_filter = TRUE)"
run "q \"SELECT COUNT(*) FROM trips_2022_part WHERE pickup_location_id = '132'\"" \
    19-require-filter-refused.txt \
    q "SELECT COUNT(*) AS trips FROM \`$DS.trips_2022_part\` WHERE pickup_location_id = '132'"

step "Step 8 · The execution plan"
run "q \"SELECT pickup_location_id, COUNT(*) AS trips FROM trips_2022 GROUP BY 1 ORDER BY trips DESC LIMIT 5\"" \
    20-groupby-run.txt \
    q "SELECT pickup_location_id, COUNT(*) AS trips FROM \`$DS.trips_2022\`
       GROUP BY 1 ORDER BY trips DESC LIMIT 5"
run "plan" 21-plan.txt plan

# ============================================================ the governance half
LAKE_URI="gs://$BUCKET/trips/2022-01/*.parquet"
BYPAY="SELECT payment_type, COUNT(*) AS trips, ROUND(AVG(tip_amount), 2) AS avg_tip"

step "Step 9 · An external table over Parquet"
run "gcloud storage ls -l gs://\$BUCKET/trips/2022-01/" 22-parquet-files.txt \
    gcloud storage ls -l "gs://$BUCKET/trips/2022-01/"
run "q \"CREATE EXTERNAL TABLE \$DS.trips_ext OPTIONS (format = 'PARQUET', uris = [...])\"" \
    23-create-external.txt \
    q "CREATE EXTERNAL TABLE \`$DS.trips_ext\`
       OPTIONS (format = 'PARQUET', uris = ['$LAKE_URI'])"
run "bq show   (trips_ext against trips_2022)" 24-external-no-stats.txt \
    bash -c "for t in trips_ext trips_2022; do
               bq --project_id=$PROJECT show --format=json $PROJECT:$DATASET.\$t \
               | jq -c '{table: .tableReference.tableId, type, numRows, numBytes}'
             done"
run "dry \"$BYPAY FROM trips_ext GROUP BY 1\"" 25-external-dry.txt \
    dry "$BYPAY FROM \`$DS.trips_ext\` GROUP BY 1 ORDER BY trips DESC"
run "q \"$BYPAY FROM trips_ext GROUP BY 1\"" 26-external-run.txt \
    q "$BYPAY FROM \`$DS.trips_ext\` GROUP BY 1 ORDER BY trips DESC"

step "Step 10 · BigLake, delegation, and a policy tag"
run "q \"CREATE EXTERNAL TABLE \$DS.trips_lake WITH CONNECTION \`\$CONNECTION\` OPTIONS (...)\"" \
    27-create-biglake.txt \
    q "CREATE EXTERNAL TABLE \`$DS.trips_lake\`
       WITH CONNECTION \`$CONNECTION\`
       OPTIONS (format = 'PARQUET', uris = ['$LAKE_URI'])"
run "as_analyst q \"SELECT COUNT(*) FROM trips_ext\"" 28-analyst-external.txt \
    as_analyst q "SELECT COUNT(*) AS trips FROM \`$DS.trips_ext\`"
run "as_analyst q \"SELECT COUNT(*) FROM trips_lake\"" 29-analyst-biglake.txt \
    as_analyst q "SELECT COUNT(*) AS trips FROM \`$DS.trips_lake\`"
bq --project_id="$PROJECT" show --schema --format=json "$PROJECT:$DATASET.trips_lake" \
  | jq --arg tag "$POLICY_TAG" \
       'map(if .name == "pickup_location_id" or .name == "dropoff_location_id"
            then . + {policyTags: {names: [$tag]}} else . end)' > "$WORKDIR/schema-tagged.json"
run "bq update --schema schema-tagged.json \$DS.trips_lake   (tag two location columns)" \
    30-attach-tag.txt \
    bq --project_id="$PROJECT" update --schema "$WORKDIR/schema-tagged.json" \
       "$PROJECT:$DATASET.trips_lake"
run "bq show --schema trips_lake   (which columns carry the tag)" 31-tagged-schema.txt \
    bash -c "bq --project_id=$PROJECT show --schema --format=json $PROJECT:$DATASET.trips_lake \
             | jq -r '.[] | \"\(.name)\t\(if .policyTags then \"policy tag \" + (.policyTags.names[0] | split(\"/\") | .[-1]) else \"-\" end)\"' \
             | column -t -s \$'\t'"
run "as_analyst q \"SELECT * FROM trips_lake LIMIT 3\"" 32-analyst-select-star.txt \
    as_analyst q "SELECT * FROM \`$DS.trips_lake\` LIMIT 3"
run "as_analyst q \"SELECT * EXCEPT (pickup_location_id, dropoff_location_id) FROM trips_lake LIMIT 3\"" \
    33-analyst-except.txt \
    as_analyst q "SELECT * EXCEPT (pickup_location_id, dropoff_location_id)
                  FROM \`$DS.trips_lake\` ORDER BY pickup_datetime LIMIT 3"
run "q \"SELECT pickup_location_id, COUNT(*) FROM trips_lake GROUP BY 1 LIMIT 3\"   (instructor)" \
    34-instructor-tagged.txt \
    q "SELECT pickup_location_id, COUNT(*) AS trips FROM \`$DS.trips_lake\`
       GROUP BY 1 ORDER BY trips DESC LIMIT 3"

step "Step 11 · Row access policies"
VENDOR="SELECT COUNT(*) AS trips, COUNT(DISTINCT vendor_id) AS vendors,
               STRING_AGG(DISTINCT vendor_id ORDER BY vendor_id) AS vendor_ids
        FROM \`$DS.trips_lake\`"
run "q \"CREATE ROW ACCESS POLICY vendor_2 ON trips_lake GRANT TO ('serviceAccount:\$ANALYST') FILTER USING (vendor_id = '2')\"" \
    35-policy-vendor.txt \
    q "CREATE ROW ACCESS POLICY vendor_2 ON \`$DS.trips_lake\`
       GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')"
run "q \"SELECT COUNT(*), vendors FROM trips_lake\"   (instructor)" \
    36-instructor-sees-nothing.txt q "$VENDOR"
run "q \"CREATE ROW ACCESS POLICY all_rows ON trips_lake GRANT TO ('user:\$ME') FILTER USING (TRUE)\"" \
    37-policy-instructor.txt \
    q "CREATE ROW ACCESS POLICY all_rows ON \`$DS.trips_lake\`
       GRANT TO ('user:$ME') FILTER USING (TRUE)"
run "q \"SELECT COUNT(*), vendors FROM trips_lake\"   (instructor)" \
    38-instructor-all.txt q "$VENDOR"
run "as_analyst q \"SELECT COUNT(*), vendors FROM trips_lake\"" \
    39-analyst-vendor.txt as_analyst q "$VENDOR"
run "q \"CREATE ROW ACCESS POLICY vendor_2 ON trips_ext ...\"   (the plain external table)" \
    40-policy-on-external.txt \
    q "CREATE ROW ACCESS POLICY vendor_2 ON \`$DS.trips_ext\`
       GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')"
run "bq ls --row_access_policies \$DS.trips_lake" 41-policies-listed.txt \
    bq --project_id="$PROJECT" ls --row_access_policies "$PROJECT:$DATASET.trips_lake"

step "Step 12 · Teardown"
run "bq rm -r -f -d \$DATASET" 42-drop-dataset.txt \
    bq --project_id="$PROJECT" rm -r -f -d "$DATASET"
run "bq rm --connection \$CONNECTION" 43-drop-connection.txt \
    bq --project_id="$PROJECT" --location=US rm -f --connection "$CONNECTION"
run "curl -X DELETE .../\$TAXONOMY" 44-drop-taxonomy.txt \
    bash -c "curl -s -X DELETE -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \
             -H 'x-goog-user-project: $PROJECT' https://datacatalog.googleapis.com/v1/$TAXONOMY; echo"
run "gcloud storage rm -r gs://\$BUCKET" 45-drop-bucket.txt \
    bash -c "gcloud storage rm -r gs://$BUCKET --project $PROJECT 2>&1 | tail -3"
run "verify: the dataset, the connection, the taxonomy and the bucket are gone" 46-verify-gone.txt \
    bash -c "bq --project_id=$PROJECT ls | grep -c $DATASET;
             bq --project_id=$PROJECT --location=US ls --connection 2>/dev/null | grep -c dsba6190-lake-$SUFFIX;
             gcloud data-catalog taxonomies list --location us --project $PROJECT --format='value(name)' | grep -c . ;
             gcloud storage ls --project $PROJECT | grep -c $BUCKET; true"

step "Mask identifiers in the capture"
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
for f in "$OUT"/*.txt; do
  sed -i '' -e "s/$ME/instructor@example.edu/g" -e "s/$NUMBER/PROJECT_NUMBER/g" "$f"
done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files into $OUT"
