#!/usr/bin/env bash
# Stage the Session 7 live demo: make the cost visible, make governance visible.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Provisions everything the hour needs that cannot be created inside it, and
# nothing the hour creates on screen. It makes one dataset, one bucket holding
# one month of taxi trips as Parquet, one BigQuery connection with read access
# to that bucket, one policy-tag taxonomy, and the second principal the
# governance steps query as. It creates no table. Steps 7, 9, 10 and 11 build
# the tables, the tag attachment and the row policies in front of the room.
#
# Run it at T minus 45. The slow part is IAM propagation on the second
# principal, measured at about five minutes on 24 September 2026, and the
# script blocks until that principal can actually run a query.
#
# Applies. Never destroys. The teardown it prints is step 12.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-07}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"

LOCATION="US"
DATASET="dsba6190_wh_$SUFFIX"
BUCKET="dsba6190-trips-$SUFFIX"
CONNECTION="dsba6190-lake-$SUFFIX"
TAXONOMY_NAME="dsba6190-$SUFFIX"
ANALYST_ID="dsba6190-analyst"
ANALYST="$ANALYST_ID@$PROJECT.iam.gserviceaccount.com"
TAXI="bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022"
ME="$(gcloud config get-value account 2>/dev/null)"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }

step "APIs"
for api in bigquery.googleapis.com bigqueryconnection.googleapis.com datacatalog.googleapis.com \
           storage.googleapis.com iamcredentials.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

step "The second principal, $ANALYST"
gcloud iam service-accounts describe "$ANALYST" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud iam service-accounts create "$ANALYST_ID" --project "$PROJECT" \
       --display-name "DSBA 6190 demo analyst, the second principal" >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$ANALYST" --project "$PROJECT" \
  --member "user:$ME" --role roles/iam.serviceAccountTokenCreator --condition=None >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/bigquery.jobUser --condition=None >/dev/null

step "The bucket and one month of trips as Parquet"
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$LOCATION" \
  --uniform-bucket-level-access --public-access-prevention >/dev/null
bq --project_id="$PROJECT" --location="$LOCATION" mk --dataset \
  --description "DSBA 6190 Session 7 live demo" "$PROJECT:$DATASET" >/dev/null
bq --project_id="$PROJECT" --location="$LOCATION" --quiet query --use_legacy_sql=false \
  "EXPORT DATA OPTIONS (uri = 'gs://$BUCKET/trips/2022-01/part-*.parquet',
                        format = 'PARQUET', overwrite = true) AS
   SELECT vendor_id, pickup_datetime, dropoff_datetime, passenger_count, trip_distance,
          payment_type, fare_amount, tip_amount, total_amount,
          pickup_location_id, dropoff_location_id
   FROM \`$TAXI\`
   WHERE pickup_datetime >= '2022-01-01' AND pickup_datetime < '2022-02-01'
   ORDER BY pickup_datetime" >/dev/null
FILES="$(gcloud storage ls "gs://$BUCKET/trips/2022-01/" | wc -l | tr -d ' ')"

step "The BigQuery connection BigLake reads through"
bq --project_id="$PROJECT" --location="$LOCATION" mk --connection \
  --connection_type=CLOUD_RESOURCE "$CONNECTION" >/dev/null
CONN_SA="$(bq --project_id="$PROJECT" --location="$LOCATION" show --connection --format=json \
             "$PROJECT.$LOCATION.$CONNECTION" | jq -r '.cloudResource.serviceAccountId')"
[ -n "$CONN_SA" ] && [ "$CONN_SA" != "null" ] || { echo "connection has no service account"; exit 1; }
# The connection's service account is created asynchronously. On 24 September
# 2026 the grant failed with "does not exist" when issued immediately.
for i in $(seq 1 18); do
  gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --project "$PROJECT" \
    --member "serviceAccount:$CONN_SA" --role roles/storage.objectViewer >/dev/null 2>&1 && break
  [ "$i" -eq 18 ] && { echo "connection service account never appeared"; exit 1; }
  sleep 10
done

step "The taxonomy and its policy tag"
cat > "${TMPDIR:-/tmp}/taxonomy-$SUFFIX.json" <<JSON
{"taxonomies": [{
  "displayName": "$TAXONOMY_NAME",
  "description": "DSBA 6190 Session 7. Location fields that re-identify a rider.",
  "activatedPolicyTypes": ["FINE_GRAINED_ACCESS_CONTROL"],
  "policyTags": [{"displayName": "trip_location",
                  "description": "Pickup and dropoff zone. With a timestamp, this identifies a person."}]
}]}
JSON
TAXONOMY="$(gcloud data-catalog taxonomies import "${TMPDIR:-/tmp}/taxonomy-$SUFFIX.json" \
              --location us --project "$PROJECT" --format=json | jq -r '.taxonomies[0].name')"
POLICY_TAG="$(gcloud data-catalog taxonomies policy-tags list --taxonomy "$TAXONOMY" \
                --location us --project "$PROJECT" --format="value(name)" | head -1)"
gcloud data-catalog taxonomies policy-tags add-iam-policy-binding "$POLICY_TAG" \
  --member "user:$ME" --role roles/datacatalog.categoryFineGrainedReader >/dev/null

step "Grant the second principal the dataset, and nothing else"
bq --project_id="$PROJECT" --location="$LOCATION" --quiet query --use_legacy_sql=false \
  "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$PROJECT.$DATASET\`
   TO 'serviceAccount:$ANALYST'" >/dev/null

step "Wait until the second principal can run a query"
T0=$(date +%s)
until CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$ANALYST" \
        bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false \
        "SELECT 1" >/dev/null 2>&1; do
  [ $(( $(date +%s) - T0 )) -gt 600 ] && { echo "impersonation not ready after 10 min"; exit 1; }
  sleep 20
done
READY=$(( $(date +%s) - T0 ))

step "The working directory"
rm -rf "$WORK"; mkdir -p "$WORK"
cp -R "$HERE/sql" "$WORK/sql"
cp "$HERE/lib.sh" "$WORK/lib.sh"
cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export DATASET="$DATASET"
export BUCKET="$BUCKET"
export CONNECTION="$PROJECT.$LOCATION.$CONNECTION"
export CONNECTION_ID="$CONNECTION"
export TAXONOMY="$TAXONOMY"
export POLICY_TAG="$POLICY_TAG"
export ANALYST="$ANALYST"
export ME="$ME"
export TAXI="$TAXI"
export WILD="bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_*"
export DS="$PROJECT.$DATASET"
source "$WORK/lib.sh"
ENVEOF

cat <<DONE

  Staged for the live demo. Nothing has been queried and no table exists.

  Working directory   $WORK
  Project             $PROJECT
  Name suffix         $SUFFIX
  Second principal    ready $READY s after the grant

  Load the names and the helpers into the shell you will teach from:

      source $WORK/env.sh

  Created and waiting for the hour:
    dataset      $DATASET          (US, empty)
    bucket       gs://$BUCKET/trips/2022-01/   ($FILES Parquet files)
    connection   $PROJECT.$LOCATION.$CONNECTION
                 reads as $CONN_SA
    taxonomy     $TAXONOMY_NAME, tag trip_location
    principal    $ANALYST
                 bigquery.jobUser on the project, dataViewer on the dataset,
                 no Cloud Storage access, no policy-tag access

  NOT created. The hour creates each of these at its own step:
    trips_2022, trips_2022_part   step 7
    trips_ext                     step 9
    trips_lake, the tag on it     step 10
    two row access policies       step 11

  Teardown is step 12, and it is also:
    bq --project_id=$PROJECT rm -r -f -d $DATASET
    bq --project_id=$PROJECT --location=$LOCATION rm -f --connection $PROJECT.$LOCATION.$CONNECTION
    gcloud storage rm -r gs://$BUCKET
    curl -s -X DELETE -H "Authorization: Bearer \$(gcloud auth print-access-token)" \\
         -H "x-goog-user-project: $PROJECT" https://datacatalog.googleapis.com/v1/$TAXONOMY
DONE
