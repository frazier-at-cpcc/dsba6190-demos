#!/usr/bin/env bash
# Stage the Session 1 live demo: one nightly job, three ways.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Queen City Trip Analytics, a fictional South End analytics company, receives
# one night of trips from a fleet customer and must roll it up before morning.
# This script generates that night (2,000,000 trips, about 135 MB), creates the
# company's bucket in us-east1, uploads the file and the rollup script, and
# enables the APIs the hour uses. It creates no VM, no job and no dataset:
# the hour creates those in front of the room.
#
# Applies. Never destroys. Run it at T minus 20.

set -euo pipefail
PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-01}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
REGION=us-east1; ZONE=us-east1-b
BUCKET="qc-nightly-$SUFFIX"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "APIs"
for api in compute.googleapis.com run.googleapis.com bigquery.googleapis.com storage.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/lib.sh" "$WORK/lib.sh"; cp -R "$HERE/job" "$WORK/job"

step "One night of trips"
python3 "$HERE/sample/make-trips.py" "$WORK/trips-2026-08-19.csv"

step "The company's bucket, the file and the job"
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" \
  --uniform-bucket-level-access --public-access-prevention \
  --default-storage-class STANDARD --quiet >/dev/null
gcloud storage buckets update "gs://$BUCKET" --update-labels \
  course=dsba6190,session=01,company=queen-city-trip-analytics --quiet >/dev/null
gcloud storage cp "$WORK/trips-2026-08-19.csv" "gs://$BUCKET/raw/" --quiet
gcloud storage cp "$WORK/job/rollup.sh" "gs://$BUCKET/job/" --quiet

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT" REGION="$REGION" ZONE="$ZONE" SUFFIX="$SUFFIX" WORK="$WORK"
export BUCKET="$BUCKET" SCRATCH="qc-scratch-$SUFFIX"
export VM="qc-nightly-vm-$SUFFIX" JOB="qc-nightly-$SUFFIX" DATASET="qc_nightly_$SUFFIX"
export CLOUDSDK_CORE_PROJECT="$PROJECT"
source "$WORK/lib.sh"
cd "$WORK"
ENVEOF

step "Staged in $(( $(date +%s) - T0 )) s"
echo "  source $WORK/env.sh"
echo "  bucket gs://$BUCKET  ($(gcloud storage du -s "gs://$BUCKET" | awk '{print $1}') bytes)"
