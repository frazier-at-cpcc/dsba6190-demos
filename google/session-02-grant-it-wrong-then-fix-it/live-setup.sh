#!/usr/bin/env bash
# Stage the Session 2 live demo: grant it wrong, then fix it.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Crown Street Markets, a fictional 40-store Charlotte grocery chain, is
# building its first analytics project. This script creates the two datasets
# (curated store sales, raw loyalty members with PII), the service account
# that stands in for the analyst, and the one grant that lets you act as
# that analyst. It grants the analyst nothing: demo.ipynb does that, wrongly
# first. No network exists yet; steps 8 to 10 build it.
#
# Applies. Never destroys. Run it about 15 minutes before you start demo.ipynb.

set -euo pipefail
PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-02}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
ANALYST="cs-analyst-$SUFFIX@$PROJECT.iam.gserviceaccount.com"
ME="$(gcloud config get-value account 2>/dev/null)"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "APIs"
for api in iam.googleapis.com bigquery.googleapis.com compute.googleapis.com iap.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

rm -rf "$WORK"; mkdir -p "$WORK"; cp "$HERE/lib.sh" "$WORK/lib.sh"
python3 "$HERE/sample/make-crown.py" "$WORK/sample"

step "Two datasets: curated and raw"
for ds in crown_curated_$SUFFIX crown_raw_$SUFFIX; do
  bq --project_id="$PROJECT" --location=US mk --dataset --label course:dsba6190 --label session:02 "$PROJECT:$ds" >/dev/null
done
bq --project_id="$PROJECT" --location=US load --skip_leading_rows=1 "crown_curated_$SUFFIX.store_sales" \
   "$WORK/sample/store_sales.csv" store_id:STRING,neighborhood:STRING,sale_date:DATE,baskets:INT64,revenue_usd:NUMERIC >/dev/null
bq --project_id="$PROJECT" --location=US load --skip_leading_rows=1 "crown_raw_$SUFFIX.loyalty_members" \
   "$WORK/sample/loyalty_members.csv" member_id:STRING,full_name:STRING,email:STRING,card_number:STRING,home_store:STRING >/dev/null
bq --project_id="$PROJECT" --location=US cp -f "crown_raw_$SUFFIX.loyalty_members" "crown_raw_$SUFFIX.members_backup" >/dev/null

step "The analyst, as a service account, and permission to act as it"
gcloud iam service-accounts create "cs-analyst-$SUFFIX" --project "$PROJECT" \
  --display-name "Crown Street analyst (stands in for the analysts group)" --quiet >/dev/null
for i in 1 2 3 4 5 6; do
  gcloud iam service-accounts add-iam-policy-binding "$ANALYST" --project "$PROJECT" \
    --member "user:$ME" --role roles/iam.serviceAccountTokenCreator --quiet >/dev/null 2>&1 && break
  sleep 10
done

# A new token-creator grant takes a minute or two to reach IAM. Wait for it so
# step 1 shows what the analyst may do, not a propagation error.
until gcloud auth print-access-token --impersonate-service-account "$ANALYST" >/dev/null 2>&1; do sleep 10; done
echo "  impersonation ready"

cat > "$WORK/probe.sh" <<'PROBE'
# Run on the private VM: can it reach Google APIs, and can it reach the internet?
hostname
for u in https://storage.googleapis.com https://bigquery.googleapis.com https://example.com; do
  printf '%-36s ' "$u"
  code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$u") && echo "$code" || echo 'no route (timed out)'
done
PROBE

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT" SUFFIX="$SUFFIX" WORK="$WORK" REGION=us-east1 ZONE=us-east1-b
export CURATED="crown_curated_$SUFFIX" RAW="crown_raw_$SUFFIX" ANALYST="$ANALYST"
export NET="crown-net-$SUFFIX" SUBNET="crown-east-$SUFFIX" VM="crown-etl-$SUFFIX" FW="crown-iap-ssh-$SUFFIX"
export CLOUDSDK_CORE_PROJECT="$PROJECT"
source "$WORK/lib.sh"
cd "$WORK"
ENVEOF
step "Staged in $(( $(date +%s) - T0 )) s"
echo "  source $WORK/env.sh"
