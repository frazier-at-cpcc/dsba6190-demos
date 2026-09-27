#!/usr/bin/env bash
# Capture the Session 5 live demo: build and harden a lake.
#
#   ./capture.sh <PROJECT_ID>
#
# Runs all twelve demo steps against a real project and writes every command's
# real output to capture/. It provisions four Cloud Storage buckets, one
# BigQuery dataset with three external tables, and about 17 MB of generated
# telemetry, holds them for roughly fifteen minutes, and destroys everything
# through an exit trap.
#
# Re-runnable. The suffix is derived per run so the global bucket namespace
# does not collide with a previous capture.
#
# Two things it touches that it cannot fully undo, both deliberate and both
# stated in the runbook's teardown checklist. A Cloud KMS key ring cannot be
# deleted, so the ring and the key persist and are reused by every later run;
# the exit trap schedules the key version for destruction, which takes effect
# after the key's scheduled-destruction window. Enabling an API is not reversed.
#
# DO NOT RUN THIS IN CLASS. It uses -auto-approve, it makes a bucket briefly
# public on purpose, it disables an encryption key on purpose, and it tears the
# estate down when it exits. live-setup.sh is the one to run before class.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/.work"
OUT="$HERE/capture"
SUFFIX="$(date +%s | tail -c 6)"

REGION="us-east1"
KEYRING="dsba6190-demo"
KEYNAME="lake-cmek"
KEY="projects/$PROJECT/locations/$REGION/keyRings/$KEYRING/cryptoKeys/$KEYNAME"

STAGING="dsba6190-staging-$SUFFIX"
LAKE="dsba6190-lake-$SUFFIX"
VAULT="dsba6190-vault-$SUFFIX"
SECURE="dsba6190-secure-$SUFFIX"
DATASET="dsba6190_lake_$SUFFIX"
FQ="$PROJECT.$DATASET"

export TF_IN_AUTOMATION=1
mkdir -p "$OUT"
rm -rf "$WORK"; mkdir -p "$WORK"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
tf   () { terraform -chdir="$WORK" "$@"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}

# A BigQuery job with a name we chose, so the byte count can be read back by a
# command an instructor can type rather than by parsing a job list.
bqrun () {  # bqrun <job_suffix> <query_outfile> <bytes_outfile> <label> <sql>
  local jid="dsba6190-$SUFFIX-$1"; local qout="$2"; local bout="$3"
  local label="$4"; local sql="$5"
  run "$label" "$qout" \
      bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache \
         --job_id="$jid" "$sql"
  run "bq show -j $jid" "$bout" bq --project_id="$PROJECT" --quiet show -j "$jid"
}

cleanup () {
  step "Cleanup"
  gcloud storage buckets update "gs://$VAULT" --project "$PROJECT" \
         --clear-retention-period >/dev/null 2>&1 || true
  tf destroy -auto-approve -no-color >/dev/null 2>&1 || true
  for b in "$STAGING" "$LAKE" "$VAULT" "$SECURE"; do
    gcloud storage buckets update "gs://$b" --project "$PROJECT" \
           --clear-retention-period >/dev/null 2>&1 || true
    gcloud storage rm --recursive --all-versions "gs://$b" --project "$PROJECT" \
           >/dev/null 2>&1 || true
  done
  bq --project_id="$PROJECT" rm -r -f -d "$DATASET" >/dev/null 2>&1 || true
  if [ -n "${VERSION:-}" ]; then
    gcloud kms keys versions destroy "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
           --location "$REGION" --project "$PROJECT" >/dev/null 2>&1 || true
  fi
  echo "  Cleanup finished. Verify with:"
  echo "    gcloud storage ls --project $PROJECT"
  echo "    bq --project_id=$PROJECT ls"
}
trap cleanup EXIT

# ============================================================ baseline estate
step "Baseline. Services, the key, the sample data, and the ungoverned bucket."
for api in storage.googleapis.com bigquery.googleapis.com cloudkms.googleapis.com \
           orgpolicy.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

gcloud kms keyrings create "$KEYRING" --location "$REGION" --project "$PROJECT" >/dev/null 2>&1 || true
gcloud kms keys create "$KEYNAME" --location "$REGION" --keyring "$KEYRING" \
       --purpose encryption --destroy-scheduled-duration=24h --project "$PROJECT" >/dev/null 2>&1 || true
VERSION="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
             --location "$REGION" --project "$PROJECT" --filter="state=ENABLED" \
             --format="value(name)" --limit=1 | awk -F/ '{print $NF}')"
if [ -z "$VERSION" ]; then
  SCHEDULED="$(gcloud kms keys versions list --key "$KEYNAME" --keyring "$KEYRING" \
                 --location "$REGION" --project "$PROJECT" --filter="state=DESTROY_SCHEDULED" \
                 --format="value(name)" --limit=1 | awk -F/ '{print $NF}')"
  if [ -n "$SCHEDULED" ]; then
    gcloud kms keys versions restore "$SCHEDULED" --key "$KEYNAME" --keyring "$KEYRING" \
           --location "$REGION" --project "$PROJECT" >/dev/null
    VERSION="$SCHEDULED"
  else
    VERSION="$(gcloud kms keys versions create --key "$KEYNAME" --keyring "$KEYRING" \
                 --location "$REGION" --project "$PROJECT" --primary \
                 --format="value(name)" | awk -F/ '{print $NF}')"
  fi
fi
gcloud kms keys versions enable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
       --location "$REGION" --project "$PROJECT" >/dev/null 2>&1 || true
SERVICE_AGENT="$(gcloud storage service-agent --project "$PROJECT" | tr -d '[:space:]')"
gcloud kms keys add-iam-policy-binding "$KEYNAME" --location "$REGION" --keyring "$KEYRING" \
       --project "$PROJECT" --member "serviceAccount:$SERVICE_AGENT" \
       --role roles/cloudkms.cryptoKeyEncrypterDecrypter >/dev/null
echo "  key version $VERSION, bound to $SERVICE_AGENT"

python3 "$HERE/sample/make-sample.py" "$WORK/sample"

cp "$HERE/01-plain/main.tf" "$WORK/main.tf"
cat > "$WORK/terraform.tfvars" <<VARS
project_id  = "$PROJECT"
name_suffix = "$SUFFIX"
region      = "$REGION"
kms_key     = "$KEY"
VARS
cp "$HERE/02-governed/lake.tf"      "$WORK/lake.tf.staged"
cp "$HERE/03-tables/tables.tf"      "$WORK/tables.tf.staged"
cp "$HERE/04-lifecycle/lake.tf"     "$WORK/lake.tf.lifecycle"
cp "$HERE/05-retention/vault.tf"    "$WORK/vault.tf.staged"
cp "$HERE/06-cmek/secure.tf"        "$WORK/secure.tf.staged"
cp "$HERE/07-partitioned/events.tf" "$WORK/events.tf.staged"

tf init -no-color >/dev/null
tf apply -auto-approve -no-color >/dev/null

# ------------------------------------------------------------------- step 1
step "Step 1. Read the governed bucket before anything runs."
cp "$WORK/lake.tf.staged" "$WORK/lake.tf"
run "cat lake.tf"     01-governed-hcl.txt    cat "$WORK/lake.tf"
run "terraform plan"  02-plan-governed.txt   tf plan -no-color

# ------------------------------------------------------------------- step 2
step "Step 2. Apply. Two buckets, one governed."
run "terraform apply" 03-apply-governed.txt tf apply -auto-approve -no-color
run "gcloud storage buckets describe  (the governed bucket)" 04-lake-controls.txt \
    gcloud storage buckets describe "gs://$LAKE" --project "$PROJECT" \
      --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"
run "gcloud storage buckets describe  (the one nobody governed)" 05-staging-controls.txt \
    gcloud storage buckets describe "gs://$STAGING" --project "$PROJECT" \
      --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"

# ------------------------------------------------------------------- step 3
step "Step 3. The four zones, and the object that lands in raw."
for z in raw validated curated archive quarantine; do
  printf 'zone: %s\ncontract: see lecture 5, slide 12\n' "$z" > "$WORK/_zone.txt"
  gcloud storage cp "$WORK/_zone.txt" "gs://$LAKE/$z/_ZONE" --project "$PROJECT" >/dev/null
done
run "gcloud storage ls  (five prefixes, zero directories)" 06-create-zones.txt \
    gcloud storage ls "gs://$LAKE" --project "$PROJECT"
run "gcloud storage cp sample/readings.csv gs://$LAKE/raw/readings/" 07-upload-raw-csv.txt \
    bash -c "cd '$WORK' && gcloud storage cp sample/readings.csv 'gs://$LAKE/raw/readings/readings.csv' --project '$PROJECT'"
run "gcloud storage ls -r  (the key is one string with slashes in it)" 08-list-zones.txt \
    gcloud storage ls -r "gs://$LAKE/raw/" --project "$PROJECT"

# ------------------------------------------------------------------- step 4
step "Step 4. Make it public. Twice."
run "gcloud storage buckets add-iam-policy-binding allUsers  (ungoverned)" 09-public-on-staging.txt \
    gcloud storage buckets add-iam-policy-binding "gs://$STAGING" --project "$PROJECT" \
      --member=allUsers --role=roles/storage.objectViewer
printf 'plant,serial,defect\ncharlotte,SN-88213,hairline crack\n' > "$WORK/_qc.csv"
gcloud storage cp "$WORK/_qc.csv" "gs://$STAGING/qc.csv" --project "$PROJECT" >/dev/null
{
  printf '$ curl https://storage.googleapis.com/%s/qc.csv\n\n' "$STAGING"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    body="$(curl -s "https://storage.googleapis.com/$STAGING/qc.csv" || true)"
    case "$body" in
      *hairline*) printf '%s\n' "$body"; break ;;
      *) [ "$i" -eq 12 ] && printf '%s\n' "$body" || sleep 10 ;;
    esac
  done
} | tee "$OUT/10-public-object-fetched.txt"
run "gcloud storage buckets add-iam-policy-binding allUsers  (governed)" 11-public-refused-lake.txt \
    gcloud storage buckets add-iam-policy-binding "gs://$LAKE" --project "$PROJECT" \
      --member=allUsers --role=roles/storage.objectViewer
run "gcloud storage objects update --add-acl-grant  (governed)" 12-acl-refused-lake.txt \
    gcloud storage objects update "gs://$LAKE/raw/readings/readings.csv" --project "$PROJECT" \
      --add-acl-grant=entity=allUsers,role=READER
run "gcloud storage buckets remove-iam-policy-binding allUsers" 13-revoke-public.txt \
    gcloud storage buckets remove-iam-policy-binding "gs://$STAGING" --project "$PROJECT" \
      --member=allUsers --role=roles/storage.objectViewer

# ------------------------------------------------------------------- step 5
step "Step 5. Versioning is the undo."
printf '{"rows": 200000, "written_by": "nightly-ingest", "status": "complete"}\n' > "$WORK/_manifest.json"
run "gcloud storage cp  (the manifest the nightly run wrote)" 14-manifest-v1.txt \
    bash -c "cd '$WORK' && gcloud storage cp _manifest.json 'gs://$LAKE/raw/readings/_manifest.json' --project '$PROJECT'"
GEN_GOOD="$(gcloud storage objects describe "gs://$LAKE/raw/readings/_manifest.json" \
              --project "$PROJECT" --format='value(generation)')"
printf '{"rows": 0, "written_by": "the-rerun-nobody-reviewed", "status": "complete"}\n' > "$WORK/_manifest.json"
gcloud storage cp "$WORK/_manifest.json" "gs://$LAKE/raw/readings/_manifest.json" \
       --project "$PROJECT" >/dev/null
run "gcloud storage cat  (after the second run)" 15-manifest-overwritten.txt \
    gcloud storage cat "gs://$LAKE/raw/readings/_manifest.json" --project "$PROJECT"
run "gcloud storage ls --all-versions --long" 16-all-versions.txt \
    gcloud storage ls --all-versions --long "gs://$LAKE/raw/readings/" --project "$PROJECT"
run "gcloud storage cp  (restore the generation)" 17-restore-generation.txt \
    gcloud storage cp "gs://$LAKE/raw/readings/_manifest.json#$GEN_GOOD" \
      "gs://$LAKE/raw/readings/_manifest.json" --project "$PROJECT"
run "gcloud storage cat" 18-manifest-restored.txt \
    gcloud storage cat "gs://$LAKE/raw/readings/_manifest.json" --project "$PROJECT"
run "gcloud storage rm  (delete the live version)" 19-delete-live-version.txt \
    gcloud storage rm "gs://$LAKE/raw/readings/_manifest.json" --project "$PROJECT"
run "gcloud storage ls  (it is gone)" 20-object-gone.txt \
    gcloud storage ls "gs://$LAKE/raw/readings/" --project "$PROJECT"
run "gcloud storage ls --all-versions  (it is not gone)" 21-versions-survive-delete.txt \
    gcloud storage ls --all-versions --long "gs://$LAKE/raw/readings/_manifest.json" \
      --project "$PROJECT"
run "gcloud storage cp  (restore it again)" 22-restore-after-delete.txt \
    gcloud storage cp "gs://$LAKE/raw/readings/_manifest.json#$GEN_GOOD" \
      "gs://$LAKE/raw/readings/_manifest.json" --project "$PROJECT"

# ------------------------------------------------------------------- step 6
step "Step 6. CSV to Parquet. Two arguments, two numbers."
run "gcloud storage cp sample/readings.parquet gs://$LAKE/curated/readings/" 23-upload-parquet.txt \
    bash -c "cd '$WORK' && gcloud storage cp sample/readings.parquet 'gs://$LAKE/curated/readings/readings.parquet' --project '$PROJECT'"
run "gcloud storage ls -l  (the same 200,000 rows, twice)" 24-object-sizes.txt \
    bash -c "gcloud storage ls -l 'gs://$LAKE/raw/readings/readings.csv' 'gs://$LAKE/curated/readings/readings.parquet' --project '$PROJECT'"
cp "$WORK/tables.tf.staged" "$WORK/tables.tf"
run "terraform apply  (two external tables)" 25-apply-tables.txt tf apply -auto-approve -no-color
bqrun csv 26-query-csv.txt 27-bytes-csv.txt \
      "bq query  (CSV)" \
      "SELECT ROUND(AVG(value), 3) AS mean_reading FROM \`$FQ.readings_csv\`"
bqrun parq 28-query-parquet.txt 29-bytes-parquet.txt \
      "bq query  (Parquet)" \
      "SELECT ROUND(AVG(value), 3) AS mean_reading FROM \`$FQ.readings_parquet\`"

# ------------------------------------------------------------------- step 7
step "Step 7. The lifecycle rule that nothing runs tonight."
cp "$WORK/lake.tf.lifecycle" "$WORK/lake.tf"
run "terraform plan" 30-plan-lifecycle.txt tf plan -no-color
run "terraform apply" 31-apply-lifecycle.txt tf apply -auto-approve -no-color
run "gcloud storage buckets describe --format='yaml(lifecycle)'" 32-lifecycle-in-place.txt \
    gcloud storage buckets describe "gs://$LAKE" --project "$PROJECT" \
      --format="yaml(name,lifecycle_config)"

# ------------------------------------------------------------------- step 8
step "Step 8. Retention, and a delete that fails."
cp "$WORK/vault.tf.staged" "$WORK/vault.tf"
run "terraform apply  (the bucket with a retention policy)" 33-apply-retention.txt \
    tf apply -auto-approve -no-color
run "gcloud storage buckets describe --format='yaml(retention_policy)'" 34-retention-policy.txt \
    gcloud storage buckets describe "gs://$VAULT" --project "$PROJECT" \
      --format="yaml(name,retention_policy)"
printf 'incident,plant,reading,recorded_at\n1,charlotte,231.4,2026-09-17T19:04:11Z\n' > "$WORK/_incident.csv"
run "gcloud storage cp  (the record that has to survive)" 35-upload-to-vault.txt \
    bash -c "cd '$WORK' && gcloud storage cp _incident.csv 'gs://$VAULT/raw/incident.csv' --project '$PROJECT'"
run "gcloud storage rm  (attempt the delete)" 36-delete-refused.txt \
    gcloud storage rm "gs://$VAULT/raw/incident.csv" --project "$PROJECT"

# ------------------------------------------------------------------- step 9
step "Step 9. CMEK, and crypto-shredding."
cp "$WORK/secure.tf.staged" "$WORK/secure.tf"
run "terraform apply  (the CMEK bucket)" 37-apply-cmek.txt tf apply -auto-approve -no-color
printf 'patient_site,serial,defect\ncharlotte,SN-88213,hairline crack\n' > "$WORK/_regulated.csv"
run "gcloud storage cp" 38-upload-cmek.txt \
    bash -c "cd '$WORK' && gcloud storage cp _regulated.csv 'gs://$SECURE/raw/regulated.csv' --project '$PROJECT'"
run "gcloud storage objects describe  (which key encrypted it)" 39-object-key-name.txt \
    gcloud storage objects describe "gs://$SECURE/raw/regulated.csv" --project "$PROJECT" \
      --format="yaml(name,kms_key)"
run "gcloud storage cat  (key enabled)" 40-read-key-enabled.txt \
    gcloud storage cat "gs://$SECURE/raw/regulated.csv" --project "$PROJECT"
run "gcloud kms keys versions disable $VERSION" 41-disable-key-version.txt \
    gcloud kms keys versions disable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
      --location "$REGION" --project "$PROJECT"

# The write path has to call Cloud KMS to wrap a new data encryption key, so it
# refuses the moment the key version is disabled. The read path can be served
# from a cached unwrapped key for a short while, so it is polled rather than
# assumed. The 10 September rehearsal saw the read refuse within seconds; an
# earlier run took longer than ten. The runbook says so, and step 9 has the
# write refusal to fill the gap.
{
  printf '$ gcloud storage cat  (read, key disabled)\n\n'
  for i in $(seq 1 18); do
    body="$(gcloud storage cat "gs://$SECURE/raw/regulated.csv" --project "$PROJECT" 2>&1 || true)"
    case "$body" in
      *KEY_DISABLED*|*ERROR*) printf '%s\n' "$body"; break ;;
      *) [ "$i" -eq 18 ] && printf '%s\n' "$body" || sleep 10 ;;
    esac
  done
} | tee "$OUT/42-read-key-disabled.txt"
run "gcloud storage cp  (write, key disabled)" 43-write-key-disabled.txt \
    bash -c "cd '$WORK' && gcloud storage cp _regulated.csv 'gs://$SECURE/raw/second.csv' --project '$PROJECT'"
run "gcloud kms keys versions enable $VERSION" 44-enable-key-version.txt \
    gcloud kms keys versions enable "$VERSION" --key "$KEYNAME" --keyring "$KEYRING" \
      --location "$REGION" --project "$PROJECT"
{
  printf '$ gcloud storage cat  (key enabled again)\n\n'
  for i in $(seq 1 18); do
    body="$(gcloud storage cat "gs://$SECURE/raw/regulated.csv" --project "$PROJECT" 2>&1 || true)"
    case "$body" in
      *hairline*) printf '%s\n' "$body"; break ;;
      *) [ "$i" -eq 18 ] && printf '%s\n' "$body" || sleep 10 ;;
    esac
  done
} | tee "$OUT/45-read-key-restored.txt"

# ------------------------------------------------------------------ step 10
step "Step 10. Partition pruning, measured."
run "gcloud storage cp -r sample/events gs://$LAKE/curated/" 46-upload-events.txt \
    bash -c "cd '$WORK' && gcloud storage cp -r sample/events 'gs://$LAKE/curated/' --project '$PROJECT'"
run "gcloud storage ls  (ten prefixes, one per day)" 47-list-partitions.txt \
    gcloud storage ls "gs://$LAKE/curated/events/" --project "$PROJECT"
cp "$WORK/events.tf.staged" "$WORK/events.tf"
run "terraform apply  (the hive-partitioned external table)" 48-apply-events-table.txt \
    tf apply -auto-approve -no-color
bqrun all 49-query-all-partitions.txt 50-bytes-all-partitions.txt \
      "bq query  (no dt filter)" \
      "SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading FROM \`$FQ.events\`"
bqrun one 51-query-one-partition.txt 52-bytes-one-partition.txt \
      "bq query  (dt = one day)" \
      "SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading FROM \`$FQ.events\` WHERE dt = '2026-09-17'"

# ------------------------------------------------------------------ step 11
step "Step 11. The guardrail above the project. Capture step."
run "gcloud projects get-ancestors" 53-project-ancestors.txt \
    gcloud projects get-ancestors "$PROJECT"
run "gcloud organizations list" 54-organizations-list.txt gcloud organizations list
run "gcloud org-policies list --project" 55-org-policies-list.txt \
    gcloud org-policies list --project="$PROJECT"
run "gcloud org-policies describe --effective" 56-org-policy-effective.txt \
    gcloud org-policies describe constraints/storage.publicAccessPrevention \
      --project="$PROJECT" --effective
cat > "$WORK/_pap.yaml" <<YAML
name: projects/$PROJECT/policies/storage.publicAccessPrevention
spec:
  rules:
  - enforce: true
YAML
run "gcloud org-policies set-policy" 57-org-policy-set-refused.txt \
    gcloud org-policies set-policy "$WORK/_pap.yaml" --project="$PROJECT"

# ------------------------------------------------------------------ step 12
step "Step 12. Teardown is a teaching step."
run "terraform destroy" 58-destroy-refused.txt tf destroy -auto-approve -no-color
run "gcloud storage buckets update --clear-retention-period" 59-clear-retention.txt \
    gcloud storage buckets update "gs://$VAULT" --project "$PROJECT" --clear-retention-period
run "terraform destroy" 60-destroy-succeeds.txt tf destroy -auto-approve -no-color

# ------------------------------------------------------------------- masking
step "Masking the account and the project number in every capture"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
python3 - "$OUT" "$PROJECT_NUMBER" "$ACCOUNT" "$HOME" <<'PY'
import pathlib, re, sys

out, number, account, home = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]

# The project id stays. It is on every slide and it is what the runbook quotes.
# The project number, the authenticated account, and the opaque troubleshooter
# token are the three things a public repository does not need.
subs = [
    (re.compile(re.escape(number)), "PROJECT_NUMBER"),
    (re.compile(re.escape(home)), "~"),
    (re.compile(re.escape(account)), "instructor@example.edu"),
    (re.compile(r"(?<=errorId=)[A-Za-z0-9_\-]{16,}"), "ERROR_ID"),
    (re.compile(r"(?<=error_info_id: )[A-Za-z0-9_\-]{16,}"), "ERROR_ID"),
]

changed = 0
for f in sorted(out.glob("*.txt")):
    text = f.read_text()
    new = text
    for pat, repl in subs:
        new = pat.sub(repl, new)
    if new != text:
        f.write_text(new)
        changed += 1
print(f"  masked in {changed} file(s)")
PY

step "Captured to $OUT"
ls -1 "$OUT"
