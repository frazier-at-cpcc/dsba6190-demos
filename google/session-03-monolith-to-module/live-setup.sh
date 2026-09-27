#!/usr/bin/env bash
# Stage the Session 3 live demo. Run this BEFORE class, not during.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Queen City Trip Analytics, a fictional South End analytics firm, created its
# nightly-trips bucket by hand in Session 1. Tonight it codifies that bucket,
# turns it into a module, and then hardens the module the way A3 asks.
#
# This script builds the working directory, initializes Terraform, writes a
# terraform.tfvars so every command is `terraform plan` or `terraform apply`
# with nothing to mistype, and writes env.sh for the notebooks.
#
# It creates nothing in the project, because step 2 must plan against an
# empty project. It never destroys. capture.sh is the headless recorder and
# destroys everything on exit; this is its opposite. Do not run capture.sh in
# front of a class.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-03}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="$(date +%s | tail -c 6)"

# Refuse to wipe a working directory whose state still tracks resources.
# Losing that state would orphan real buckets and a VM.
if [ -f "${WORK:?}/terraform.tfstate" ] && \
   python3 -c "import json,sys; sys.exit(0 if json.load(open('${WORK:?}/terraform.tfstate')).get('resources') else 1)"; then
  echo "  ${WORK} still tracks resources. Tear down first:" >&2
  echo "      cd ${WORK} && terraform destroy -auto-approve" >&2
  exit 1
fi

rm -rf "${WORK:?}"
mkdir -p "$WORK/stages"
cp "$HERE/01-monolith/main.tf" "$WORK/main.tf"

cat > "$WORK/terraform.tfvars" <<VARS
project_id    = "$PROJECT"
bucket_suffix = "$SUFFIX"
VARS

# Staged so no step is five minutes of live authoring.
cp -R "$HERE/04-module/modules" "$WORK/modules"
cp "$HERE/04-module/main.tf" "$WORK/main.tf.module"
cp "$HERE/02-storage-class/main.tf" "$WORK/main.tf.nearline"
cp "$HERE/03-rename/main.tf" "$WORK/main.tf.renamed"
for s in 05-validate 06-protect 07-foreach 08-vm; do
  cp -R "$HERE/$s" "$WORK/stages/$s"
done

# Last night's trips, a small stand-in for the file a fleet drops each night.
cat > "$WORK/trips-2026-09-02.csv" <<'CSV'
trip_id,pickup_zone,dropoff_zone,pickup_ts,fare_usd
100001,South End,Uptown,2026-09-02T22:14:05,14.20
100002,NoDa,Plaza Midwood,2026-09-02T22:31:47,9.85
100003,Uptown,Airport,2026-09-02T23:02:10,31.40
100004,Dilworth,South End,2026-09-02T23:40:33,8.10
CSV

( cd "$WORK" && terraform init -no-color >/dev/null )

# Read by the LOAD cell of prep.ipynb and demo.ipynb.
cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export SUFFIX="$SUFFIX"
export BUCKET="dsba6190-raw-$SUFFIX"
export DEV_BUCKET="dsba6190-dev-raw-$SUFFIX"
export TEST_BUCKET="dsba6190-test-raw-$SUFFIX"
export PROD_BUCKET="dsba6190-prod-raw-$SUFFIX"
export VM="dsba6190-trips-vm-$SUFFIX"
export ZONE="us-east1-b"
export WORKDIR="$WORK"
export TF_IN_AUTOMATION=1
export CLOUDSDK_CORE_PROJECT="$PROJECT"
ENVEOF

cat <<DONE

  Staged for the live demo. Nothing exists in the project yet.

  Working directory   $WORK
  Project             $PROJECT
  Suffix              $SUFFIX
  Monolith bucket     dsba6190-raw-$SUFFIX
  Module buckets      dsba6190-{dev,test,prod}-raw-$SUFFIX
  VM                  dsba6190-trips-vm-$SUFFIX

  Staged edits:
    main.tf.nearline        step 4, storage class changed
    main.tf.renamed         step 5, bucket renamed
    main.tf.module          step 7, root calling the module twice
    stages/05-validate      step 8, validation and enforced labels
    stages/06-protect       step 9, prevent_destroy and force_destroy
    stages/07-foreach       step 10, environments from one map
    stages/08-vm            step 11, the Lab 3 VM as a module
    trips-2026-09-02.csv    step 9, the object that makes prod worth guarding

  Verify now, while there is time to fix it:

      cd $WORK && terraform plan

  Expect: Plan: 1 to add, 0 to change, 0 to destroy.

  Tear down after class (step 13 does this):

      cd $WORK && gcloud storage rm "gs://dsba6190-prod-raw-$SUFFIX/**"; terraform destroy -auto-approve

DONE
