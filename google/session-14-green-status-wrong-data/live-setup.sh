#!/usr/bin/env bash
# Stage the Session 14 live demo: green status, wrong data.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Generates sixty nights of Crown Street Markets store sales from a seeded
# script, puts the raw files in a labelled Cloud Storage bucket, and loads
# fifty-nine of them into a labelled, date-partitioned BigQuery table. Last
# night's file is left for step 1, where the nightly load runs in demo.ipynb.
# It also loads thirty nights of load outcomes for the error-budget step.
#
# Applies. Never destroys. The teardown it prints is step 8.
set -euo pipefail
PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-14}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
DATASET="store_ops_$SUFFIX"
BUCKET="s14-store-sales-raw-$SUFFIX"
LOG="s14-dq-$SUFFIX"
METRIC="s14_dq_red_$SUFFIX"
LAST_NIGHT="$(python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=1))')"
LAST_ID="${LAST_NIGHT//-/}"
FIRST_NIGHT="$(python3 -c "import datetime as d; print(d.date.fromisoformat('$LAST_NIGHT') - d.timedelta(days=59))")"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }

step "Generate sixty nights of store sales, the last one $LAST_NIGHT"
rm -rf "$WORK"; mkdir -p "$WORK"
python3 "$HERE/sample/make-store-sales.py" "$WORK/sample" "$LAST_NIGHT"

step "Create the raw bucket and upload the files"
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location US \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$BUCKET" --project "$PROJECT" \
  --update-labels=team=replenishment,pipeline=nightly-store-sales,env=demo >/dev/null
gcloud storage cp -r "$WORK/sample/raw" "$WORK/sample/incoming" "gs://$BUCKET/" --project "$PROJECT" \
  --quiet 2>&1 | tail -1

step "Create the partitioned, labelled table and backfill fifty-nine nights"
bq --project_id="$PROJECT" --location=US mk --dataset \
   --label team:replenishment --label env:demo \
   --description "DSBA 6190 Session 14, Crown Street Markets store sales" "$PROJECT:$DATASET" >/dev/null
bq --project_id="$PROJECT" --location=US mk --table \
   --time_partitioning_field sale_date --time_partitioning_type DAY \
   --label team:replenishment --label pipeline:nightly-store-sales --label env:demo \
   --description "One row per register basket. Loaded nightly; read by the replenishment dashboard at 06:00." \
   "$PROJECT:$DATASET.store_sales" \
   sale_date:DATE,store_id:STRING,region:STRING,neighborhood:STRING,register_id:STRING,basket_id:STRING,items:INT64,basket_value:FLOAT64,payment_type:STRING >/dev/null
URIS="$(cd "$WORK/sample/raw" && ls | grep -v "dt=$LAST_NIGHT" | sed "s|^|gs://$BUCKET/raw/|; s|$|/sales.csv|" | paste -sd, -)"
bq --project_id="$PROJECT" --location=US --quiet load \
   --label=pipeline:backfill --label="run:$SUFFIX" \
   --source_format=CSV --skip_leading_rows=1 --source_column_match=NAME \
   "$PROJECT:$DATASET.store_sales" "$URIS"
bq --project_id="$PROJECT" --location=US --quiet load \
   --label=pipeline:backfill --label="run:$SUFFIX" \
   --source_format=CSV --skip_leading_rows=1 \
   "$PROJECT:$DATASET.load_runs" "$WORK/sample/load_runs.csv" \
   sale_date:DATE,state:STRING,finished_at:DATETIME,rows_loaded:INT64,corrected_at:DATETIME

cp -R "$HERE/sql" "$WORK/sql"
cp "$HERE/lib.sh" "$WORK/lib.sh"
for f in metric.yaml policy.json lifecycle.json; do
  sed -e "s/@@PROJECT@@/$PROJECT/g" -e "s/@@SUFFIX@@/$SUFFIX/g" \
      -e "s/@@LOG@@/$LOG/g" -e "s/@@METRIC@@/$METRIC/g" "$HERE/monitoring/$f" > "$WORK/$f"
done

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export DATASET="$DATASET"
export DS="$PROJECT.$DATASET"
export BACKUP="store_ops_bak_$SUFFIX"
export BUCKET="$BUCKET"
export LOG="$LOG"
export METRIC="$METRIC"
export LAST_NIGHT="$LAST_NIGHT"
export LAST_ID="$LAST_ID"
export FIRST_NIGHT="$FIRST_NIGHT"
source "$WORK/lib.sh"
cd "$WORK"
ENVEOF

cat <<DONE

  Staged. Fifty-nine nights loaded; last night ($LAST_NIGHT) waits for step 1.

      source $WORK/env.sh

  Table     $PROJECT.$DATASET.store_sales
  Bucket    gs://$BUCKET
  Teardown  step 8 of demo.ipynb, or
            bq --project_id=$PROJECT rm -r -f -d $DATASET
            gcloud storage rm -r gs://$BUCKET
DONE
