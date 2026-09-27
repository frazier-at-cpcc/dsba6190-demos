#!/usr/bin/env bash
# Stage the Session 4 live demo. Run this BEFORE class, not during.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# This demo starts from an estate that already exists, so unlike Session 3 this
# script DOES apply. It creates the baseline with LOCAL state, because step 1
# reads that local state file and step 3 migrates it. It also creates two
# buckets by hand, out of band, because steps 8 and 10 need resources that
# Terraform did not build and a bucket made ten seconds ago is not legacy.
#
# It does NOT create the state bucket. Creating the state bucket is step 2.
#
# It does NOT destroy anything. capture.sh is the headless recorder and tears
# everything down through an exit trap; this is its opposite. Do not run
# capture.sh in front of a class.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-04}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="$(date +%s | tail -c 6)"

STATE_BUCKET="dsba6190-tfstate-$SUFFIX"
RAW_BUCKET="dsba6190-raw-$SUFFIX"
LEGACY_BUCKET="dsba6190-legacy-$SUFFIX"
ANNEX_BUCKET="dsba6190-annex-$SUFFIX"

rm -rf "$WORK"
mkdir -p "$WORK"

cp "$HERE/01-local-state/main.tf" "$WORK/main.tf"

cat > "$WORK/terraform.tfvars" <<VARS
project_id  = "$PROJECT"
name_suffix = "$SUFFIX"
VARS

# Staged edits, so no step is five minutes of live authoring.
cp "$HERE/03-lock/main.tf"                    "$WORK/main.tf.sleep"
cp "$HERE/05-state-mv/main.tf"                "$WORK/main.tf.renamed"
cp "$HERE/06-destroy-controls/main.tf"        "$WORK/main.tf.protected"
cp "$HERE/06-destroy-controls/main-forced.tf" "$WORK/main.tf.forced"
cp "$HERE/04-import/legacy-guess.tf"          "$WORK/legacy.tf.guess"
cp "$HERE/04-import/legacy-matched.tf"        "$WORK/legacy.tf.matched"

# Two templates, because neither a backend block nor a Terraform 1.5 import
# block may contain a variable. That restriction is the lecture's watch-for.
sed "s|__STATE_BUCKET__|$STATE_BUCKET|" \
    "$HERE/02-remote-backend/backend.tf.tmpl" > "$WORK/backend.tf.staged"
sed -e "s|__PROJECT_ID__|$PROJECT|" -e "s|__ANNEX_BUCKET__|$ANNEX_BUCKET|" \
    "$HERE/04-import/annex-import-block.tf.tmpl" > "$WORK/annex.tf.staged"

# The two buckets nobody wrote down. Step 8 adopts them.
gcloud storage buckets create "gs://$LEGACY_BUCKET" --project "$PROJECT" \
       --location=US-CENTRAL1 --default-storage-class=NEARLINE >/dev/null
gcloud storage buckets update "gs://$LEGACY_BUCKET" --project "$PROJECT" \
       --update-labels=environment=prod,owner=unknown >/dev/null
gcloud storage buckets create "gs://$ANNEX_BUCKET" --project "$PROJECT" \
       --location=US-WEST1 --default-storage-class=COLDLINE \
       --uniform-bucket-level-access >/dev/null
gcloud storage buckets update "gs://$ANNEX_BUCKET" --project "$PROJECT" \
       --update-labels=environment=prod,owner=unknown >/dev/null

( cd "$WORK" && terraform init -no-color >/dev/null )
( cd "$WORK" && terraform apply -auto-approve -no-color >/dev/null )

# Read by the LOAD cell of prep.ipynb and demo.ipynb.
cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export SUFFIX="$SUFFIX"
export STATE_BUCKET="$STATE_BUCKET"
export RAW_BUCKET="$RAW_BUCKET"
export LEGACY_BUCKET="$LEGACY_BUCKET"
export ANNEX_BUCKET="$ANNEX_BUCKET"
export TOPIC="dsba6190-events-$SUFFIX"
export STATE_OBJECT="gs://$STATE_BUCKET/envs/dev/default.tfstate"
export WORKDIR="$WORK"
ENVEOF

cat <<DONE

  Staged for the live demo, and the baseline is applied.

  Working directory   $WORK
  Project             $PROJECT
  Name suffix         $SUFFIX

  Applied with LOCAL state, which is what step 1 reads and step 3 migrates:
    $RAW_BUCKET        google_storage_bucket.raw
    dsba6190-events-$SUFFIX     google_pubsub_topic.events
    random_password.db_admin        the value step 1 finds in the file

  Created by hand, out of band, because steps 8 and 10 need resources
  Terraform did not build:
    $LEGACY_BUCKET     US-CENTRAL1, NEARLINE, fine-grained access
    $ANNEX_BUCKET      US-WEST1, COLDLINE, uniform access

  NOT created, because creating it is step 2:
    $STATE_BUCKET

  Staged file variants:
    backend.tf.staged   step 3, the backend block with the bucket filled in
    main.tf.sleep       step 5, adds the resource slow enough to hold the lock
    legacy.tf.guess     step 8, the wrong configuration, written from memory
    legacy.tf.matched   step 8, the configuration the plan asked for
    annex.tf.staged     step 8, the plannable import block
    main.tf.renamed     step 10, the bucket address changed to landing
    main.tf.protected   step 11, prevent_destroy on the bucket
    main.tf.forced      step 11, force_destroy on the bucket

  Verify now, while there is time to fix it:

      cd $WORK && terraform plan

  Expect: No changes. Your infrastructure matches the configuration.

  Tear down after class. All four lines, in this order:

      cd $WORK && terraform destroy -auto-approve
      gcloud storage rm --recursive --all-versions gs://$STATE_BUCKET --project $PROJECT
      gcloud storage rm --recursive gs://$LEGACY_BUCKET --project $PROJECT
      gcloud storage rm --recursive gs://$ANNEX_BUCKET --project $PROJECT

  Terraform will not clean up the state bucket, which was created by hand, or
  the legacy bucket, which step 10 told it to forget. The annex bucket is only
  left behind if the demonstration stopped before step 8 adopted it; a 404 on
  that line means step 8 ran and there is nothing to remove. A 404 on the
  state bucket line means step 2 never ran.

  Confirm with:

      gcloud storage ls --project $PROJECT

DONE
