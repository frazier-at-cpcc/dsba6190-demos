#!/usr/bin/env bash
# Capture the Session 2 live demo: grant it wrong, then fix it.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh into .work/, runs every demonstration step, writes each
# command's output to capture/, and deletes everything through an exit trap:
# the analyst's grants, the service account, both datasets, the VM, the
# firewall rule, the subnet and the network. Cost: under $0.05.
#
# It stages, runs and deletes everything in one pass. To follow the steps
# yourself, prefer prep.ipynb and demo.ipynb.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"; OUT="$HERE/capture"; mkdir -p "$OUT"
export SUFFIX="$(date +%s | tail -c 6)"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () { local label="$1"; local out="$OUT/$2"; shift 2
          { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"; }
cleanup () {
  step "Cleanup"
  local sa="cs-analyst-${SUFFIX:?}@$PROJECT.iam.gserviceaccount.com"
  for r in roles/editor roles/bigquery.jobUser; do
    gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$sa" --role "$r" --condition=None --quiet >/dev/null 2>&1 || true
  done
  gcloud compute instances delete "crown-etl-$SUFFIX" --zone us-east1-b --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud compute firewall-rules delete "crown-iap-ssh-$SUFFIX" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud compute networks subnets delete "crown-east-$SUFFIX" --region us-east1 --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud compute networks delete "crown-net-$SUFFIX" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  gcloud iam service-accounts delete "$sa" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  for ds in "crown_curated_$SUFFIX" "crown_raw_$SUFFIX"; do bq --project_id="$PROJECT" rm -r -f -d "$ds" >/dev/null 2>&1 || true; done
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"
SA="serviceAccount:$ANALYST"
wait_until () { local want="$1"; shift; local s ok; s=$(date +%s)
  while :; do
    if "$@" >/dev/null 2>&1; then ok=allow; else ok=deny; fi
    [ "$ok" = "$want" ] && break
    [ $(( $(date +%s) - s )) -gt 420 ] && { echo "still waiting after 420 s"; return 0; }
    sleep 10
  done
  echo "took effect after $(( $(date +%s) - s )) s"; }
READ_RAW="bq --project_id=$PROJECT --location=US query --use_legacy_sql=false --format=pretty 'SELECT member_id, email, card_number FROM \`$RAW.loyalty_members\` LIMIT 3'"

step "Step 1 · Crown Street's two datasets"
run "bq ls" 01-datasets.txt bash -c "bq --project_id=$PROJECT ls | grep crown_"
run "q \"SELECT * FROM crown_raw.loyalty_members LIMIT 3\"   (what an analyst never needs)" 02-raw.txt \
    q "SELECT * FROM \`$RAW.loyalty_members\` LIMIT 3"
run "as_analyst bq ls   (the analyst has no grant yet)" 03-analyst-nothing.txt bash -c \
    "n=\$(CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=$ANALYST bq --project_id=$PROJECT ls --format=json 2>/dev/null | jq 'length' 2>/dev/null); echo \"datasets the analyst can see: \${n:-0}\""

step "Step 2 · How big each role is"
run "count the permissions in three roles" 04-role-sizes.txt bash -c "
for r in roles/editor roles/bigquery.dataViewer roles/bigquery.jobUser; do
  printf '%-28s %5s permissions\n' \$r \$(gcloud iam roles describe \$r --format=json | jq '.includedPermissions | length')
done"

step "Step 3 · Grant it wrong"
run "gcloud projects add-iam-policy-binding \$PROJECT --member \$ANALYST --role roles/editor" 05-grant-editor.txt \
    bash -c "gcloud projects add-iam-policy-binding $PROJECT --member $SA --role roles/editor --condition=None --quiet | grep -B1 -A2 'cs-analyst'"
run "wait until the grant takes effect" 06-propagation.txt wait_until allow as_analyst bash -c "$READ_RAW"

step "Step 4 · What Editor lets the analyst do"
run "as_analyst: read card numbers" 07-analyst-reads-pii.txt as_analyst bash -c "$READ_RAW"
run "as_analyst: bq rm -f -t \$RAW.members_backup" 08-analyst-deletes.txt \
    as_analyst bq --project_id="$PROJECT" rm -f -t "${RAW:?}.members_backup"
run "bq ls \$RAW   (the backup is gone)" 08b-raw-after.txt bq --project_id="$PROJECT" ls "$PROJECT:$RAW"
run "as_analyst: gcloud compute instances list   (and every other service)" 09-analyst-compute.txt \
    as_analyst gcloud compute instances list --project "$PROJECT"

step "Step 5 · Fix it"
run "remove Editor; grant jobUser on the project" 10-fix-project.txt bash -c "
gcloud projects remove-iam-policy-binding $PROJECT --member $SA --role roles/editor --condition=None --quiet >/dev/null && echo 'removed roles/editor'
gcloud projects add-iam-policy-binding $PROJECT --member $SA --role roles/bigquery.jobUser --condition=None --quiet >/dev/null && echo 'granted roles/bigquery.jobUser on the project'"
run "q \"GRANT roles/bigquery.dataViewer ON SCHEMA \$CURATED TO \$ANALYST\"   (one dataset)" 11-fix-dataset.txt \
    q "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$PROJECT.$CURATED\` TO 'serviceAccount:$ANALYST'"

step "Step 6 · Read the policy"
run "gcloud projects get-iam-policy --filter=\$ANALYST" 17-policy-project.txt \
    gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
      --filter="bindings.members:$ANALYST" --format="table(bindings.role,bindings.members)"
run "bq show \$CURATED   (the dataset's own access list)" 18-policy-dataset.txt bash -c \
    "bq --project_id=$PROJECT show --format=prettyjson $PROJECT:$CURATED | jq -c '.access[]'"

step "Step 7 · Nobody granted this one"
run "the default Compute Engine service account's roles" 19-default-sa.txt \
    gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
      --filter="bindings.members:-compute@developer.gserviceaccount.com" --format="table(bindings.role,bindings.members)"
run "gcloud iam service-accounts keys list --iam-account \$ANALYST   (no key ever left Google)" 20-keys.txt \
    gcloud iam service-accounts keys list --iam-account "$ANALYST" --project "$PROJECT" \
      --format="table(name.basename(),keyType,validAfterTime.date('%Y-%m-%d'))"

step "Step 8 · A private network"
run "gcloud compute networks create \$NET --subnet-mode custom" 21-network.txt \
    gcloud compute networks create "$NET" --subnet-mode custom --project "$PROJECT"
run "gcloud compute networks subnets create \$SUBNET --range 10.20.0.0/24   (no Private Google Access)" 22-subnet.txt \
    gcloud compute networks subnets create "$SUBNET" --network "$NET" --region "$REGION" --range 10.20.0.0/24 --project "$PROJECT"
run "gcloud compute instances create \$VM --no-address" 23-vm.txt \
    gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-micro --subnet "$SUBNET" --no-address \
      --image-family debian-12 --image-project debian-cloud --shielded-secure-boot --labels course=dsba6190,session=02 --project "$PROJECT"
run "gcloud compute firewall-rules list --filter network=\$NET   (none: only the implied rules)" 24-firewall-none.txt \
    gcloud compute firewall-rules list --filter="network:$NET" --project "$PROJECT"
sleep 30
run "timeout 60 gcloud compute ssh \$VM --tunnel-through-iap   (implied deny ingress)" 25-ssh-timeout.txt \
    bash -c "S=\$(date +%s); timeout 60 gcloud compute ssh $VM --zone $ZONE --tunnel-through-iap --project $PROJECT --quiet --strict-host-key-checking=no --command 'hostname' -- -o ConnectTimeout=20 2>&1 | grep -v '^$' | tail -3; echo \"gave up after \$(( \$(date +%s) - S )) s\""

step "Step 9 · Open one door"
run "gcloud compute firewall-rules create \$FW --allow tcp:22 --source-ranges 35.235.240.0/20" 26-firewall-iap.txt \
    gcloud compute firewall-rules create "$FW" --network "$NET" --direction INGRESS --allow tcp:22 \
      --source-ranges 35.235.240.0/20 --project "$PROJECT"
sleep 15
SSH="gcloud compute ssh $VM --zone $ZONE --tunnel-through-iap --project $PROJECT --quiet --strict-host-key-checking=no"
run "cat probe.sh" 26b-probe-script.txt cat "$WORK/probe.sh"
run "ssh in, then try Google APIs and the internet" 27-probe-before.txt bash -c "timeout 120 $SSH --command 'bash -s' < \"$WORK/probe.sh\" 2>&1 | grep -v 'Warning\|^$\|External IP'"

step "Step 10 · Private Google Access"
run "gcloud compute networks subnets update \$SUBNET --enable-private-ip-google-access" 28-pga.txt \
    gcloud compute networks subnets update "$SUBNET" --region "$REGION" --enable-private-ip-google-access --project "$PROJECT"
sleep 20
run "the same probe" 29-probe-after.txt bash -c "timeout 120 $SSH --command 'bash -s' < \"$WORK/probe.sh\" 2>&1 | grep -v 'Warning\|^$\|External IP'"

step "Step 11 · After: least privilege, scoped"
run "wait until the raw table is refused" 12-propagation-fix.txt wait_until deny as_analyst bash -c "$READ_RAW"
run "as_analyst: revenue by neighborhood from the curated dataset" 13-analyst-curated.txt \
    as_analyst bq --project_id="$PROJECT" --location=US query --use_legacy_sql=false --format=pretty \
      "SELECT neighborhood, SUM(baskets) AS baskets, ROUND(SUM(revenue_usd)) AS revenue_usd FROM \`$CURATED.store_sales\` GROUP BY 1 ORDER BY 3 DESC LIMIT 5"
run "as_analyst: read card numbers" 14-analyst-raw-denied.txt as_analyst bash -c "$READ_RAW"
run "as_analyst: bq rm -f -t \$CURATED.store_sales" 15-analyst-delete-denied.txt \
    as_analyst bq --project_id="$PROJECT" rm -f -t "${CURATED:?}.store_sales"
run "as_analyst: gcloud compute instances list" 16-analyst-compute-denied.txt \
    as_analyst gcloud compute instances list --project "$PROJECT"

step "Step 12 · Teardown"
run "delete the VM, the rule, the subnet, the network, the grants, the service account, the datasets" 30-teardown.txt bash -c "
gcloud compute instances delete ${VM:?} --zone ${ZONE:?} --quiet 2>&1 | tail -1
gcloud compute firewall-rules delete ${FW:?} --quiet 2>&1 | tail -1
gcloud compute networks subnets delete ${SUBNET:?} --region ${REGION:?} --quiet 2>&1 | tail -1
gcloud compute networks delete ${NET:?} --quiet 2>&1 | tail -1
gcloud projects remove-iam-policy-binding $PROJECT --member serviceAccount:${ANALYST:?} --role roles/bigquery.jobUser --condition=None --quiet >/dev/null && echo 'removed jobUser'
gcloud iam service-accounts delete ${ANALYST:?} --quiet 2>&1 | tail -1
bq --project_id=$PROJECT rm -r -f -d ${CURATED:?} && bq --project_id=$PROJECT rm -r -f -d ${RAW:?} && echo 'datasets removed'"
run "verify" 31-verify.txt bash -c "
gcloud compute networks list --filter='name~crown-net' 2>&1 | tail -1
gcloud iam service-accounts list --filter='email~cs-analyst' 2>&1 | tail -1
bq --project_id=$PROJECT ls | grep -c crown_ || true"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ME="$(gcloud config get-value account 2>/dev/null)"
for f in "$OUT"/*.txt; do sed -i '' -e "s/$NUMBER/PROJECT_NUMBER/g" -e "s/$ME/instructor@example.edu/g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
