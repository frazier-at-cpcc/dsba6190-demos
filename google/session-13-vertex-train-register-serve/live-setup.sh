#!/usr/bin/env bash
# Stage the Session 13 live demo: Vertex AI training, registry, and serving.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Queen City Trip Analytics' fleet fuel-cost model. Before class this script
# runs two custom training jobs (ridge and boosted trees) on the prebuilt
# scikit-learn 1.6 container, registers the ridge model, creates an endpoint
# and deploys it. Deployment is the slow part. It registers the boosted model
# nowhere: step 7 does that in front of the room.
#
# Applies. Never destroys. Run it at T minus 60.
set -euo pipefail
PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-13}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
REGION=us-central1
BUCKET="qc-fuel-$SUFFIX"
TRAIN_IMAGE=us-docker.pkg.dev/vertex-ai/training/sklearn-cpu.1-6:latest
SERVE_IMAGE=us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "APIs, bucket and data"
gcloud services enable aiplatform.googleapis.com --project "$PROJECT" >/dev/null
gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" --uniform-bucket-level-access >/dev/null
gcloud storage cp "$HERE/sample/auto-mpg.data" "gs://$BUCKET/data/auto-mpg.data" >/dev/null
rm -rf "${WORK:?}"; mkdir -p "$WORK"
python3 - "$HERE/sample/auto-mpg.data" > "$WORK/batch-input.jsonl" <<'PY'
import sys, json
for line in open(sys.argv[1]):
    f = line.split()
    if "?" in f[3]: continue
    print(json.dumps([float(f[1]), float(f[2]), float(f[3]), float(f[4]), float(f[5]), int(f[6]), int(f[7])]))
PY
gcloud storage cp "$WORK/batch-input.jsonl" "gs://$BUCKET/batch/input.jsonl" >/dev/null

step "The trainer package"
python3 - "$HERE" "$WORK/qc_fuel_trainer-0.1.tar.gz" <<'PKG'
import io, sys, tarfile, pathlib
here, out = pathlib.Path(sys.argv[1]), sys.argv[2]
with tarfile.open(out, "w:gz") as tar:
    for f in ["setup.py", "trainer/__init__.py", "trainer/train.py"]:
        tar.add(here / f, arcname=f"qc_fuel_trainer-0.1/{f}")
    body = b"Metadata-Version: 1.0\nName: qc_fuel_trainer\nVersion: 0.1\n"
    info = tarfile.TarInfo("qc_fuel_trainer-0.1/PKG-INFO"); info.size = len(body)
    tar.addfile(info, io.BytesIO(body))
PKG
gcloud storage cp "$WORK/qc_fuel_trainer-0.1.tar.gz" "gs://$BUCKET/pkg/" >/dev/null

step "Two training jobs, in parallel"
for m in ridge boosted; do
  gcloud ai custom-jobs create --project "$PROJECT" --region "$REGION" --display-name "qc-fuel-$m-$SUFFIX" \
    --worker-pool-spec="machine-type=e2-standard-4,replica-count=1,executor-image-uri=$TRAIN_IMAGE,python-module=trainer.train" \
    --python-package-uris="gs://$BUCKET/pkg/qc_fuel_trainer-0.1.tar.gz" \
    --args="--data=gs://$BUCKET/data/auto-mpg.data,--model=$m,--model_dir=gs://$BUCKET/models/$m/model" \
    --format="value(name)" 2>"$WORK/job-$m.log" | grep -o 'projects/[^ ]*/customJobs/[0-9]*' > "$WORK/job-$m.name" || true
done
for m in ridge boosted; do
  [ -s "$WORK/job-$m.name" ] || { echo "training job $m was not created:"; tail -20 "$WORK/job-$m.log"; exit 1; }
done
for m in ridge boosted; do
  until s=$(gcloud ai custom-jobs describe "$(cat "$WORK/job-$m.name")" --region "$REGION" --format="value(state)") && \
        [[ "$s" =~ SUCCEEDED|FAILED|CANCELLED ]]; do sleep 20; done
  echo "  $m: $s"; [ "$s" = "JOB_STATE_SUCCEEDED" ] || { echo "training failed"; exit 1; }
done

step "Register the ridge model, create an endpoint, deploy"
MODEL=$(gcloud ai models upload --project "$PROJECT" --region "$REGION" --display-name "qc-fuel-$SUFFIX" \
          --artifact-uri "gs://$BUCKET/models/ridge/model" --container-image-uri "$SERVE_IMAGE" \
          --version-aliases=ridge --format="value(model)" > "$WORK/upload.log" 2>&1 || true
        grep -o 'models/[0-9]*' "$WORK/upload.log" | head -1 || true)
[ -n "$MODEL" ] || MODEL="models/$(gcloud ai models list --region "$REGION" --filter="displayName=qc-fuel-$SUFFIX" --format='value(name.basename())' | head -1)"
ENDPOINT=$(gcloud ai endpoints create --project "$PROJECT" --region "$REGION" --display-name "qc-fuel-$SUFFIX" \
             --format="value(name)" > "$WORK/endpoint.log" 2>&1 || true
           grep -o 'endpoints/[0-9]*' "$WORK/endpoint.log" | head -1 || true)
[ -n "$ENDPOINT" ] || ENDPOINT="endpoints/$(gcloud ai endpoints list --region "$REGION" --filter="displayName=qc-fuel-$SUFFIX" --format='value(name.basename())' | head -1)"
[ "${MODEL##*/}" ] || { echo "model upload failed:"; tail -20 "$WORK/upload.log"; exit 1; }
[ "${ENDPOINT##*/}" ] || { echo "endpoint creation failed:"; tail -20 "$WORK/endpoint.log"; exit 1; }
echo "  model $MODEL, endpoint $ENDPOINT; deploying (about 20 minutes)"
gcloud ai endpoints deploy-model "${ENDPOINT##*/}" --project "$PROJECT" --region "$REGION" --model "${MODEL##*/}" \
  --display-name "qc-fuel-ridge" --machine-type n1-standard-2 --min-replica-count 1 --max-replica-count 1 \
  > "$WORK/deploy.log" 2>&1 || { echo "deploy failed:"; tail -20 "$WORK/deploy.log"; exit 1; }

cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export REGION="$REGION"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export BUCKET="$BUCKET"
export MODEL_ID="${MODEL##*/}"
export ENDPOINT_ID="${ENDPOINT##*/}"
export JOB_RIDGE="$(cat "$WORK/job-ridge.name")"
export JOB_BOOSTED="$(cat "$WORK/job-boosted.name")"
export SERVE_IMAGE="$SERVE_IMAGE"
cd "$WORK"
ENVEOF
READY=$(( $(date +%s) - T0 ))
cat <<DONE

  Staged in $(( READY / 60 )) min $(( READY % 60 )) s. The ridge model is deployed and billing.

      source $WORK/env.sh

  Endpoint  $ENDPOINT   (one n1-standard-2 node, billing until undeployed)
  Model     $MODEL (alias ridge); the boosted artifact waits for step 7
  Teardown  step 10 undeploys; step 11 deletes the endpoint, the model and gs://$BUCKET
DONE
