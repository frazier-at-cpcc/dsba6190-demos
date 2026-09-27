#!/usr/bin/env bash
# Capture the Session 4 live demo: migrate state, then break it.
#
#   ./capture.sh <PROJECT_ID>
#
# Runs all eleven demo steps against a real project and writes every command's
# real output to capture/. It provisions four Cloud Storage buckets, one
# Pub/Sub topic, one generated password and one local time_sleep, holds them
# for roughly twenty minutes, and destroys everything through an exit trap.
# Empty buckets and an idle topic cost a fraction of a cent.
#
# Re-runnable. The suffix is derived per run so the global bucket namespace
# does not collide with a previous capture.
#
# It uses -auto-approve, it kills a running apply on purpose, and it tears
# the estate down when it exits. To follow the steps yourself, prefer
# prep.ipynb and demo.ipynb.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/.work"
WORK_B="$HERE/.work-b"
OUT="$HERE/capture"
SUFFIX="$(date +%s | tail -c 6)"

STATE_BUCKET="dsba6190-tfstate-$SUFFIX"
RAW_BUCKET="dsba6190-raw-$SUFFIX"
LEGACY_BUCKET="dsba6190-legacy-$SUFFIX"
ANNEX_BUCKET="dsba6190-annex-$SUFFIX"
TOPIC="dsba6190-events-$SUFFIX"
PREFIX="envs/dev"
STATE_OBJECT="gs://$STATE_BUCKET/$PREFIX/default.tfstate"

export TF_IN_AUTOMATION=1
mkdir -p "$OUT"
rm -rf "$WORK" "$WORK_B"; mkdir -p "$WORK" "$WORK_B"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
tf   () { terraform -chdir="$WORK" "$@"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}

cleanup () {
  step "Cleanup"
  cp "$HERE/06-destroy-controls/main-forced.tf" "$WORK/main.tf" 2>/dev/null || true
  rm -f "$WORK/legacy.tf" 2>/dev/null || true
  tf destroy -auto-approve -no-color >/dev/null 2>&1 || true
  for b in "$STATE_BUCKET" "$RAW_BUCKET" "$LEGACY_BUCKET" "$ANNEX_BUCKET"; do
    gcloud storage rm --recursive --all-versions "gs://$b" --project "$PROJECT" >/dev/null 2>&1 || true
  done
  gcloud pubsub topics delete "$TOPIC" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  echo "  Cleanup finished. Verify with: gcloud storage ls --project $PROJECT"
}
trap cleanup EXIT

# ============================================================ baseline estate
step "Baseline. Apply with LOCAL state, and create two buckets by hand."
cp "$HERE/01-local-state/main.tf" "$WORK/main.tf"
cat > "$WORK/terraform.tfvars" <<VARS
project_id  = "$PROJECT"
name_suffix = "$SUFFIX"
VARS
sed "s|__STATE_BUCKET__|$STATE_BUCKET|" \
    "$HERE/02-remote-backend/backend.tf.tmpl" > "$WORK/backend.tf.staged"
sed -e "s|__PROJECT_ID__|$PROJECT|" -e "s|__ANNEX_BUCKET__|$ANNEX_BUCKET|" \
    "$HERE/04-import/annex-import-block.tf.tmpl" > "$WORK/annex.tf.staged"

gcloud storage buckets create "gs://$LEGACY_BUCKET" --project "$PROJECT" \
       --location=US-CENTRAL1 --default-storage-class=NEARLINE >/dev/null
gcloud storage buckets update "gs://$LEGACY_BUCKET" --project "$PROJECT" \
       --update-labels=environment=prod,owner=unknown >/dev/null
gcloud storage buckets create "gs://$ANNEX_BUCKET" --project "$PROJECT" \
       --location=US-WEST1 --default-storage-class=COLDLINE \
       --uniform-bucket-level-access >/dev/null
gcloud storage buckets update "gs://$ANNEX_BUCKET" --project "$PROJECT" \
       --update-labels=environment=prod,owner=unknown >/dev/null

tf init -no-color >/dev/null
tf apply -auto-approve -no-color >/dev/null
PW="$(tf output -raw db_admin_password)"

# ------------------------------------------------------------------- step 1
step "Step 1. Read the state you already have."
run "terraform state list"                       01-state-list.txt              tf state list
run "terraform output"                           02-output-redacted.txt         tf output
run "terraform state show random_password.db_admin" 03-state-show-redacted.txt  tf state show -no-color random_password.db_admin
run "ls -l terraform.tfstate" 04-state-file-on-disk.txt bash -c "cd '$WORK' && ls -l terraform.tfstate"
run "grep -o '\"result\": \"[^\"]*\"' terraform.tfstate" 05-password-in-plain-text.txt \
    bash -c "cd '$WORK' && grep -o '\"result\": \"[^\"]*\"' terraform.tfstate"

# ------------------------------------------------------------------- step 2
step "Step 2. Bootstrap the state bucket, with versioning."
run "gcloud storage buckets create" 06-create-state-bucket.txt \
    gcloud storage buckets create "gs://$STATE_BUCKET" --project "$PROJECT" \
      --location=US-EAST1 --uniform-bucket-level-access --public-access-prevention
run "gcloud storage buckets update --versioning" 07-enable-versioning.txt \
    gcloud storage buckets update "gs://$STATE_BUCKET" --project "$PROJECT" --versioning
run "gcloud storage buckets describe" 08-state-bucket-controls.txt \
    gcloud storage buckets describe "gs://$STATE_BUCKET" --project "$PROJECT" \
      --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"

# ------------------------------------------------------------------- step 3
step "Step 3. The backend block, and the migration."
cp "$WORK/backend.tf.staged" "$WORK/backend.tf"
run "cat backend.tf" 09-backend-block.txt cat "$WORK/backend.tf"
run "terraform init -migrate-state" 10-init-migrate.txt \
    tf init -no-color -migrate-state -force-copy
run "gcloud storage ls -r" 11-state-object-in-bucket.txt \
    gcloud storage ls -r "gs://$STATE_BUCKET" --project "$PROJECT"
run "gcloud storage cat | grep result" 12-password-in-the-bucket.txt \
    bash -c "gcloud storage cat '$STATE_OBJECT' --project '$PROJECT' | grep -o '\"result\": \"[^\"]*\"'"

# ------------------------------------------------------------------- step 4
step "Step 4. Plan says no changes."
run "terraform plan" 13-plan-no-changes.txt tf plan -no-color
run "ls -l terraform.tfstate*" 14-local-copy-left-behind.txt \
    bash -c "cd '$WORK' && ls -l terraform.tfstate* 2>&1; echo; grep -o '\"result\": \"[^\"]*\"' terraform.tfstate* 2>&1 | head -4"
rm -f "$WORK"/terraform.tfstate "$WORK"/terraform.tfstate.backup

# ------------------------------------------------------------------- step 5
step "Step 5. Two terminals, one lock."
cp "$HERE/03-lock/main.tf" "$WORK/main.tf"
cp "$WORK/main.tf" "$WORK/terraform.tfvars" "$WORK/backend.tf" "$WORK_B/"
terraform -chdir="$WORK_B" init -no-color >/dev/null
terraform -chdir="$WORK" apply -auto-approve -no-color > "$OUT/15-apply-holding-the-lock.txt" 2>&1 &
APPLY_PID=$!
sleep 25
run "terraform plan   (second terminal)" 16-lock-refused.txt \
    terraform -chdir="$WORK_B" plan -no-color
wait "$APPLY_PID" || true
sed -i '' '1i\
$ terraform apply   (first terminal)\
' "$OUT/15-apply-holding-the-lock.txt"

# ------------------------------------------------------------------- step 6
step "Step 6. The crashed run, and force-unlock."
terraform -chdir="$WORK" apply -auto-approve -no-color -replace=time_sleep.slow_apply \
    > "$OUT/17-apply-then-killed.txt" 2>&1 &
KILL_PID=$!
sleep 25
kill -9 "$KILL_PID" 2>/dev/null || true
pkill -9 -f "terraform-provider-time" 2>/dev/null || true
wait "$KILL_PID" 2>/dev/null || true
printf '$ terraform apply     (killed with SIGKILL after 25 seconds)\n\n%s\n' \
    "$(cat "$OUT/17-apply-then-killed.txt")" > "$OUT/17-apply-then-killed.txt.new"
mv "$OUT/17-apply-then-killed.txt.new" "$OUT/17-apply-then-killed.txt"
run "terraform plan" 18-stale-lock.txt tf plan -no-color
LOCK_ID="$(grep -Eo 'ID: *[0-9a-f-]+' "$OUT/18-stale-lock.txt" | head -1 | awk '{print $2}')"
echo "  lock id: ${LOCK_ID:-none}"
run "terraform force-unlock $LOCK_ID" 19-force-unlock.txt \
    tf force-unlock -force -no-color "$LOCK_ID"
run "terraform plan" 20-plan-after-unlock.txt tf plan -no-color
tf apply -auto-approve -no-color >/dev/null

# ------------------------------------------------------------------- step 7
step "Step 7. Versioning is the undo."
GOOD_GEN="$(gcloud storage objects describe "$STATE_OBJECT" --project "$PROJECT" \
            --format='value(generation)')"
run "gcloud storage rm  (the state object)" 21-state-object-deleted.txt \
    gcloud storage rm "$STATE_OBJECT" --project "$PROJECT"
run "terraform plan" 22-plan-with-no-state.txt tf plan -no-color
run "gcloud storage ls --all-versions" 23-generations.txt \
    gcloud storage ls --all-versions --long "gs://$STATE_BUCKET/$PREFIX/" --project "$PROJECT"
run "gcloud storage cp  (restore a generation)" 24-restore-generation.txt \
    gcloud storage cp "$STATE_OBJECT#$GOOD_GEN" "$STATE_OBJECT" --project "$PROJECT"
run "terraform plan" 25-plan-restored.txt tf plan -no-color

# ------------------------------------------------------------------- step 8
step "Step 8. Import what somebody built by hand."
cp "$HERE/04-import/legacy-guess.tf" "$WORK/legacy.tf"
run "cat legacy.tf" 26-legacy-guess.txt cat "$WORK/legacy.tf"
run "terraform import google_storage_bucket.legacy" 27-import-cli.txt \
    tf import -no-color google_storage_bucket.legacy "$PROJECT/$LEGACY_BUCKET"
run "terraform plan" 28-plan-after-import.txt tf plan -no-color
cp "$HERE/04-import/legacy-matched.tf" "$WORK/legacy.tf"
run "terraform plan" 29-plan-config-matches.txt tf plan -no-color
cp "$WORK/annex.tf.staged" "$WORK/annex.tf"
run "cat annex.tf" 30-import-block.txt cat "$WORK/annex.tf"
run "terraform plan" 31-plan-import-block.txt tf plan -no-color
run "terraform apply" 32-apply-import-block.txt tf apply -auto-approve -no-color

# ------------------------------------------------------------------- step 9
step "Step 9. Drift, and which side should win."
run "gcloud storage buckets update --update-labels" 33-drift-label.txt \
    gcloud storage buckets update "gs://$RAW_BUCKET" --project "$PROJECT" \
      --update-labels=owner=someone-at-2am
run "terraform plan" 34-plan-drift-label.txt tf plan -no-color
run "terraform apply -refresh-only" 35-refresh-only.txt \
    tf apply -refresh-only -auto-approve -no-color
run "terraform plan" 36-plan-still-drifted.txt tf plan -no-color
run "gcloud pubsub topics delete" 37-drift-delete.txt \
    gcloud pubsub topics delete "$TOPIC" --project "$PROJECT" --quiet
run "terraform plan" 38-plan-drift-delete.txt tf plan -no-color
run "terraform apply" 39-apply-reconcile.txt tf apply -auto-approve -no-color

# ------------------------------------------------------------------ step 10
step "Step 10. Surgery on the record."
run "terraform state list" 40-state-list-full.txt tf state list
run "terraform state rm google_storage_bucket.legacy" 41-state-rm.txt \
    tf state rm google_storage_bucket.legacy
run "terraform plan" 42-plan-after-rm.txt tf plan -no-color
rm -f "$WORK/legacy.tf"
run "terraform plan   (after removing legacy.tf)" 43-plan-forgotten.txt tf plan -no-color
cp "$HERE/05-state-mv/main.tf" "$WORK/main.tf"
run "terraform plan" 44-plan-address-change.txt tf plan -no-color
run "terraform state mv" 45-state-mv.txt \
    tf state mv google_storage_bucket.raw google_storage_bucket.landing
run "terraform plan" 46-plan-after-mv.txt tf plan -no-color

# ------------------------------------------------------------------ step 11
step "Step 11. Refuse to destroy, then permit it."
echo "quarterly totals, and nobody has a copy" > "$WORK/report.csv"
run "gcloud storage cp  (data arrives out of band)" 47-data-arrives.txt \
    gcloud storage cp "$WORK/report.csv" "gs://$RAW_BUCKET/report.csv" --project "$PROJECT"
cp "$HERE/06-destroy-controls/main.tf" "$WORK/main.tf"
run "terraform destroy" 48-prevent-destroy.txt tf destroy -auto-approve -no-color
cp "$HERE/05-state-mv/main.tf" "$WORK/main.tf"
run "terraform destroy -target=google_storage_bucket.landing" 49-bucket-not-empty.txt \
    tf destroy -auto-approve -no-color -target=google_storage_bucket.landing
cp "$HERE/06-destroy-controls/main-forced.tf" "$WORK/main.tf"
run "terraform apply" 50-force-destroy-apply.txt tf apply -auto-approve -no-color
run "terraform destroy" 51-destroy-succeeds.txt tf destroy -auto-approve -no-color

# ------------------------------------------------------------------- masking
step "Masking the generated password in every capture"
python3 - "$OUT" "$PW" <<'PY'
import pathlib, re, sys
out, pw = pathlib.Path(sys.argv[1]), sys.argv[2]
mask = "*" * len(pw)
# The literal value, for outputs that print it raw, and the JSON-escaped value
# as Terraform writes it into state, where & becomes \u0026 and " becomes \".
pat = re.compile(r'(?<="result": ")[^"]*(?=")')
n = 0
for f in sorted(out.glob("*.txt")):
    lines = f.read_text().split("\n")
    changed = False
    for i, line in enumerate(lines):
        if line.startswith("$ "):        # never rewrite the echoed command
            continue
        new = pat.sub(mask, line.replace(pw, mask))
        if new != line:
            lines[i] = new
            changed = True
    if changed:
        f.write_text("\n".join(lines))
        n += 1
print(f"  masked in {n} file(s)")
PY

step "Captured to $OUT"
ls -1 "$OUT"
