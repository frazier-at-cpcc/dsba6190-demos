#!/usr/bin/env bash
# Capture the Session 3 demonstration: monolith to module, then hardened.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh into .work/, runs all thirteen steps against a
# real project, and writes every command's real output to capture/. It
# creates one monolith bucket, three module-built buckets and one e2-micro VM
# for about two minutes, and deletes everything through an exit trap that
# names each resource it made. Cost of one run: well under one cent.
#
# It stages, runs and deletes everything in one pass. To follow the steps
# yourself, prefer prep.ipynb and demo.ipynb.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/.work"
OUT="$HERE/capture"
export TF_IN_AUTOMATION=1

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () {  # run <label> <outfile> <command...>   (never aborts; expected errors are captured)
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; ( cd "$WORK" && "$@" ) 2>&1 || true; } | tee "$out"
}
expect () {  # expect <outfile> <pattern>: stop the run if a step did not do what the walkthrough says
  grep -q -E "$2" "$OUT/$1" || { echo "!!! $1 does not contain: $2" >&2; exit 1; }
}
tf () { terraform "$@" -no-color; }

cleanup () {
  step "Cleanup: every resource this run could have created, by name"
  [ -n "${SUFFIX:-}" ] || { echo "  No suffix recorded, so nothing was created."; return; }
  gcloud compute instances update "${VM:?}" --zone "${ZONE:?}" --project "$PROJECT" \
    --no-deletion-protection --quiet >/dev/null 2>&1 || true
  gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --project "$PROJECT" \
    --quiet >/dev/null 2>&1 || true
  for b in "dsba6190-raw-${SUFFIX:?}" "dsba6190-raw-renamed-${SUFFIX:?}" \
           "dsba6190-dev-raw-${SUFFIX:?}" "dsba6190-test-raw-${SUFFIX:?}" "dsba6190-prod-raw-${SUFFIX:?}"; do
    gcloud storage rm -r "gs://${b:?}" --project "$PROJECT" >/dev/null 2>&1 || true
  done
  echo "  Remaining with suffix ${SUFFIX}:"
  gcloud storage buckets list --project "$PROJECT" --filter="name~${SUFFIX:?}" --format="value(name)" 2>/dev/null
  gcloud compute instances list --project "$PROJECT" --filter="name~${SUFFIX:?}" --format="value(name)" 2>/dev/null
  echo "  (nothing listed above means nothing remains)"
}
trap cleanup EXIT

rm -rf "${OUT:?}"; mkdir -p "$OUT"

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORK" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORK/env.sh"

# ------------------------------------------------------------------ steps 1-3
step "Step 1 · The monolith"
run "cat main.tf" 01-monolith.txt cat main.tf

step "Step 2 · Read the diff before you cause it"
run "terraform plan" 02-plan-create.txt tf plan
expect 02-plan-create.txt "Plan: 1 to add, 0 to change, 0 to destroy"

step "Step 3 · Apply, then apply again"
run "terraform apply" 03-apply-first.txt tf apply -auto-approve
expect 03-apply-first.txt "Apply complete! Resources: 1 added"
run "terraform apply   (again, nothing edited)" 04-apply-idempotent.txt tf apply -auto-approve
expect 04-apply-idempotent.txt "No changes"

# ------------------------------------------------------------------ steps 4-6
step "Step 4 · Update in place"
cp "$WORK/main.tf.nearline" "$WORK/main.tf"
run "cp main.tf.nearline main.tf && terraform plan" 05-plan-update.txt tf plan
run "terraform apply" 06-apply-update.txt tf apply -auto-approve
expect 06-apply-update.txt "0 added, 1 changed, 0 destroyed"

step "Step 5 · Destroy and recreate. Stop here."
cp "$WORK/main.tf.renamed" "$WORK/main.tf"
run "cp main.tf.renamed main.tf && terraform plan" 07-plan-replace.txt tf plan
expect 07-plan-replace.txt "forces replacement"
cp "$WORK/main.tf.nearline" "$WORK/main.tf"

step "Step 6 · Drift, made outside Terraform"
run "gcloud storage buckets update gs://\$BUCKET --update-labels=owner=someone-at-2am   (or the Console)" \
    08-drift-edit.txt gcloud storage buckets update "gs://${BUCKET:?}" --update-labels=owner=someone-at-2am --project "$PROJECT"
run "terraform plan" 09-plan-drift.txt tf plan
expect 09-plan-drift.txt "someone-at-2am"

# ------------------------------------------------------------------ step 7
step "Step 7 · One module, two environments"
run "terraform destroy" 10-destroy-monolith.txt tf destroy -auto-approve
expect 10-destroy-monolith.txt "Destroy complete! Resources: 1 destroyed"
cp "$WORK/main.tf.module" "$WORK/main.tf"
run "cp main.tf.module main.tf && terraform init" 11-init-module.txt bash -c "terraform init -no-color | grep -v '^$'"
run "terraform plan" 12-plan-module.txt tf plan
run "terraform apply" 13-apply-module.txt tf apply -auto-approve
expect 13-apply-module.txt "2 added, 0 changed, 0 destroyed"

# ------------------------------------------------------------------ step 8
step "Step 8 · Validation, and labels a caller cannot override"
cp -R "$WORK/stages/05-validate/." "$WORK/"
( cd "$WORK" && terraform init -no-color >/dev/null )
cp "$WORK/main.tf.typo" "$WORK/main.tf"
run "cp main.tf.typo main.tf && terraform plan" 14-plan-typo.txt tf plan
expect 14-plan-typo.txt "environment must be one of"
cp "$WORK/stages/05-validate/main.tf" "$WORK/main.tf"
run "cp stages/05-validate/main.tf main.tf && terraform plan" 15-plan-labels.txt tf plan
expect 15-plan-labels.txt "fleet-dashboards"
run "terraform apply" 16-apply-labels.txt tf apply -auto-approve
expect 16-apply-labels.txt "Apply complete"
run "terraform output dev_labels" 17-output-labels.txt tf output dev_labels

# ------------------------------------------------------------------ step 9
step "Step 9 · Safe deletion: prevent_destroy, then force_destroy"
cp -R "$WORK/stages/06-protect/." "$WORK/"
run "cp -R stages/06-protect/. . && terraform apply" 18-apply-protect.txt tf apply -auto-approve
expect 18-apply-protect.txt "force_destroy"
run "gcloud storage cp trips-2026-09-02.csv gs://\$PROD_BUCKET/raw/" 19-upload-trips.txt \
    gcloud storage cp trips-2026-09-02.csv "gs://${PROD_BUCKET:?}/raw/" --project "$PROJECT"
run "terraform destroy" 20-destroy-refused.txt tf destroy -auto-approve
expect 20-destroy-refused.txt "prevent_destroy"
cp "$WORK/modules/data-lake/main.tf.unguarded" "$WORK/modules/data-lake/main.tf"
run "cp modules/data-lake/main.tf.unguarded modules/data-lake/main.tf && terraform destroy -target=module.prod_lake" \
    21-destroy-nonempty.txt tf destroy -auto-approve -target=module.prod_lake
expect 21-destroy-nonempty.txt "force_destroy"
run "gcloud storage ls gs://\$PROD_BUCKET/raw/   (the data survived)" 22-prod-survived.txt \
    gcloud storage ls "gs://${PROD_BUCKET:?}/raw/" --project "$PROJECT"

# ------------------------------------------------------------------ step 10
step "Step 10 · Environments from one map"
cp -R "$WORK/stages/07-foreach/." "$WORK/"
run "cp -R stages/07-foreach/. . && terraform init && terraform plan" 23-plan-moved.txt \
    bash -c "terraform init -no-color >/dev/null && terraform plan -no-color"
expect 23-plan-moved.txt "Plan: 0 to add, 0 to change, 0 to destroy"
run "terraform apply" 24-apply-moved.txt tf apply -auto-approve
cp "$WORK/main.tf.test" "$WORK/main.tf"
run "cp main.tf.test main.tf && terraform plan   (test added to the map)" 25-plan-add-test.txt tf plan
expect 25-plan-add-test.txt "Plan: 1 to add, 0 to change, 0 to destroy"
run "terraform apply" 26-apply-add-test.txt tf apply -auto-approve
expect 26-apply-add-test.txt "1 added, 0 changed, 0 destroyed"

# ------------------------------------------------------------------ step 11
step "Step 11 · The trips VM as a module"
cp -R "$WORK/stages/08-vm/." "$WORK/"
( cd "$WORK" && terraform init -no-color >/dev/null )
run "cp -R stages/08-vm/. . && terraform init && terraform plan -var machine_type=n2-standard-32" \
    27-plan-n2.txt tf plan -var machine_type=n2-standard-32
expect 27-plan-n2.txt "machine_type must be"
T0=$(date +%s)
run "terraform apply   (e2-micro, environment prod)" 28-apply-vm.txt tf apply -auto-approve
expect 28-apply-vm.txt "1 added, 0 changed, 0 destroyed"
run "gcloud compute instances delete \$VM --zone \$ZONE" 29-gcloud-delete-refused.txt \
    gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --project "$PROJECT" --quiet
run "gcloud compute instances describe \$VM --format='table(name,machineType.basename(),status,deletionProtection)'" 30-vm-survived.txt \
    gcloud compute instances describe "${VM:?}" --zone "${ZONE:?}" --project "$PROJECT" \
      --format="table(name,machineType.basename(),status,deletionProtection)"
run "terraform apply -var vm_environment=dev   (protection off, through Terraform)" 31-apply-unprotect.txt \
    tf apply -auto-approve -var vm_environment=dev
expect 31-apply-unprotect.txt "0 added, 1 changed, 0 destroyed"
cp "$WORK/stages/07-foreach/main.tf.test" "$WORK/main.tf"
run "cp stages/07-foreach/main.tf.test main.tf && terraform apply   (the module call removed)" 32-apply-remove-vm.txt \
    tf apply -auto-approve
expect 32-apply-remove-vm.txt "0 added, 0 changed, 1 destroyed"
T1=$(date +%s)
LIFE=$(( T1 - T0 ))
{ printf '$ the VM, priced\n\n'
  printf 'wall clock, apply to destroyed          %d s\n' "$LIFE"
  python3 -c "
life=$LIFE
# Cloud Billing Catalog, us-east1 on-demand, read 27 September 2026:
# E2 core \$0.02181159/h, E2 RAM \$0.00292353/GiB-h, N2 core \$0.031611/h, N2 RAM \$0.004237/GiB-h
micro = 0.25*0.02181159 + 1*0.00292353      # e2-micro: 0.25 vCPU of core time, 1 GiB
n2_32 = 32*0.031611 + 128*0.004237          # n2-standard-32: 32 vCPU, 128 GiB
print(f'machine-hours                           {life/3600:.4f}')
print(f'e2-micro list price                     \${micro:.6f} per hour')
print(f'e2-micro for this run                   \${life/3600*micro:.6f}')
print(f'n2-standard-32 list price               \${n2_32:.4f} per hour')
print(f'n2-standard-32 for this run             \${life/3600*n2_32:.4f}')
print(f'n2-standard-32 left on for 730 hours    \${730*n2_32:,.2f}')
"; } | tee "$OUT/33-vm-cost.txt"

# ------------------------------------------------------------------ step 12
step "Step 12 · Drift as an exit code, and what makes a run reproducible"
run "terraform plan -detailed-exitcode; echo \"exit code \$?\"" 34-exitcode-clean.txt \
    bash -c "terraform plan -detailed-exitcode -no-color | tail -3; echo \"exit code \${PIPESTATUS[0]}\""
expect 34-exitcode-clean.txt "exit code 0"
run "gcloud storage buckets update gs://\$PROD_BUCKET --update-labels=owner=someone-at-2am" 35-drift-edit.txt \
    gcloud storage buckets update "gs://${PROD_BUCKET:?}" --update-labels=owner=someone-at-2am --project "$PROJECT"
run "terraform plan -detailed-exitcode; echo \"exit code \$?\"" 36-exitcode-drift.txt \
    bash -c "terraform plan -detailed-exitcode -no-color | grep -E 'owner|Plan:'; echo \"exit code \${PIPESTATUS[0]}\""
expect 36-exitcode-drift.txt "exit code 2"
run "cat .terraform.lock.hcl" 37-lockfile.txt bash -c "sed -n '1,12p' .terraform.lock.hcl"
run "terraform providers" 38-providers.txt tf providers
run "terraform version" 39-version.txt tf version

# ------------------------------------------------------------------ step 13
step "Step 13 · Teardown, and proof that nothing remains"
run "gcloud storage rm gs://\$PROD_BUCKET/**   (delete the data on purpose, first)" 40-empty-prod.txt \
    gcloud storage rm "gs://${PROD_BUCKET:?}/**" --project "$PROJECT"
run "terraform destroy" 41-destroy.txt tf destroy -auto-approve
expect 41-destroy.txt "Destroy complete"
run "gcloud storage buckets list --filter=name~\$SUFFIX; gcloud compute instances list --filter=name~\$SUFFIX" \
    42-verify.txt bash -c "gcloud storage buckets list --project $PROJECT --filter='name~${SUFFIX:?}' --format='value(name)'; \
                          gcloud compute instances list --project $PROJECT --filter='name~${SUFFIX:?}' --format='value(name)'; \
                          echo \"buckets: \$(gcloud storage buckets list --project $PROJECT --filter='name~${SUFFIX:?}' --format='value(name)' | wc -l | tr -d ' ')\"; \
                          echo \"instances: \$(gcloud compute instances list --project $PROJECT --filter='name~${SUFFIX:?}' --format='value(name)' | wc -l | tr -d ' ')\""
run "terraform state list" 43-state-empty.txt bash -c "terraform state list; echo \"resources in state: \$(terraform state list | wc -l | tr -d ' ')\""

step "Mask identifiers"
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
for f in "$OUT"/*.txt; do
  sed -i '' -E -e "s/${NUMBER:?}/PROJECT_NUMBER/g" \
      -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/instructor@example.edu/g' "$f"
done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files into $OUT"
