#!/usr/bin/env bash
# Capture the Session 13 Vertex half: training, registry, serving, batch.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh (two training jobs, one registered and deployed
# model), then records the demonstration steps: the finished jobs and their cost
# shape, a second model version with its lineage, online predictions, a batch
# prediction job, the undeploy, and teardown. Everything is deleted through an
# exit trap. Cost: roughly $1, most of it the deployed node and the batch job.
#
# It stages, runs and deletes everything in one pass. To follow the steps
# yourself, prefer prep.ipynb and demo.ipynb.
set -euo pipefail
PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"; OUT="$HERE/capture"; mkdir -p "$OUT"
export SUFFIX="$(date +%s | tail -c 6)"
REGION=us-central1; BUCKET="qc-fuel-$SUFFIX"
API="https://$REGION-aiplatform.googleapis.com/v1/projects/$PROJECT/locations/$REGION"
step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () { local label="$1"; local out="$OUT/$2"; shift 2
          { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"; }
tok () { gcloud auth print-access-token; }
cleanup () {
  step "Cleanup"
  for e in $(gcloud ai endpoints list --region "$REGION" --project "$PROJECT" --filter="displayName=qc-fuel-$SUFFIX" --format="value(name.basename())" 2>/dev/null); do
    for dm in $(gcloud ai endpoints describe "$e" --region "$REGION" --project "$PROJECT" --format="value(deployedModels[].id)" 2>/dev/null | tr ';' ' '); do
      gcloud ai endpoints undeploy-model "$e" --deployed-model-id "$dm" --region "$REGION" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
    done
    gcloud ai endpoints delete "$e" --region "$REGION" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  done
  for m in $(gcloud ai models list --region "$REGION" --project "$PROJECT" --filter="displayName=qc-fuel-$SUFFIX" --format="value(name.basename())" 2>/dev/null); do
    gcloud ai models delete "$m" --region "$REGION" --project "$PROJECT" --quiet >/dev/null 2>&1 || true
  done
  gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT" >/dev/null 2>&1 || true
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"

step "Step 2 · The training jobs, already finished"
run "gcloud ai custom-jobs describe <ridge> <boosted>" 01-jobs.txt bash -c "
for j in $JOB_RIDGE $JOB_BOOSTED; do
  gcloud ai custom-jobs describe \$j --region $REGION --format='value(displayName,state,createTime.date(%H:%M:%S),endTime.date(%H:%M:%S),jobSpec.workerPoolSpecs[0].machineSpec.machineType,jobSpec.workerPoolSpecs[0].containerSpec.imageUri)'
done"
run "gcloud logging read <the training log line with the test error>" 02-train-log.txt bash -c "
for j in $JOB_RIDGE $JOB_BOOSTED; do
  gcloud logging read \"resource.type=ml_job AND resource.labels.job_id=\${j##*/} AND test_mae_mpg\" --project $PROJECT --limit 1 --format='value(textPayload,jsonPayload.message)'
done"
run "gcloud storage ls -l gs://\$BUCKET/models/*/model/" 03-artifacts.txt gcloud storage ls -l "gs://$BUCKET/models/*/model/"

step "Step 7 · The registry, and a second version"
run "gcloud ai models upload --parent-model \$MODEL_ID --version-aliases=boosted (the boosted artifact)" 04-upload-v2.txt \
    gcloud ai models upload --project "$PROJECT" --region "$REGION" --display-name "qc-fuel-$SUFFIX" \
      --parent-model "projects/$PROJECT/locations/$REGION/models/$MODEL_ID" \
      --artifact-uri "gs://$BUCKET/models/boosted/model" --container-image-uri "$SERVE_IMAGE" --version-aliases=boosted
run "gcloud ai models list-version \$MODEL_ID" 05-versions.txt \
    gcloud ai models list-version "$MODEL_ID" --region "$REGION" --project "$PROJECT" \
      --format="table(versionId,versionAliases.list(),versionCreateTime.date('%H:%M:%S'),artifactUri.basename())"
run "gcloud ai models describe \$MODEL_ID   (container and artifact)" 06-describe.txt \
    gcloud ai models describe "$MODEL_ID" --region "$REGION" --project "$PROJECT" \
      --format="yaml(displayName,versionId,versionAliases,artifactUri,containerSpec.imageUri)"

step "Step 8 · Online prediction"
cat > "$WORKDIR/request.json" <<'JSON'
{"instances": [[8, 350, 165, 3693, 11.5, 70, 1], [4, 97, 88, 2130, 14.5, 71, 3], [4, 140, 86, 2790, 15.6, 82, 1]]}
JSON
run "cat request.json   (raw vehicle attributes, no hand normalization)" 07-request.txt cat "$WORKDIR/request.json"
run "time gcloud ai endpoints predict \$ENDPOINT_ID --json-request request.json" 08-predict.txt bash -c "
S=\$(date +%s%N 2>/dev/null || date +%s); gcloud ai endpoints predict $ENDPOINT_ID --region $REGION --project $PROJECT --json-request request.json 2>&1 | grep -v Using"
run "fuel cost per 20-mile trip at \$3.20 a gallon" 09-fuel-cost.txt bash -c "
gcloud ai endpoints predict $ENDPOINT_ID --region $REGION --project $PROJECT --json-request request.json --format=json 2>/dev/null \
 | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"predictions\"]; [print(f\"vehicle {i+1}: {m:5.1f} mpg  fuel for 20 miles \${20/m*3.20:5.2f}\") for i,m in enumerate(p)]'"

step "Step 9 · Batch prediction"
cat > "$WORKDIR/batch.json" <<JSON
{"displayName": "qc-fuel-batch-$SUFFIX",
 "model": "projects/$PROJECT/locations/$REGION/models/$MODEL_ID@boosted",
 "inputConfig": {"instancesFormat": "jsonl", "gcsSource": {"uris": ["gs://$BUCKET/batch/input.jsonl"]}},
 "outputConfig": {"predictionsFormat": "jsonl", "gcsDestination": {"outputUriPrefix": "gs://$BUCKET/batch/out"}},
 "dedicatedResources": {"machineSpec": {"machineType": "n1-standard-2"}, "startingReplicaCount": 1, "maxReplicaCount": 1}}
JSON
B0=$(date +%s)
run "curl -X POST .../batchPredictionJobs -d @batch.json   (392 vehicles, the boosted version)" 10-batch-submit.txt bash -c "
curl -s -X POST -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" -H 'Content-Type: application/json' \
  $API/batchPredictionJobs -d @batch.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"name\",d)); print(d.get(\"state\",\"\"))'"
BJ=$(grep -o 'batchPredictionJobs/[0-9]*' "$OUT/10-batch-submit.txt" | head -1)
until s=$(curl -s -H "Authorization: Bearer $(tok)" "$API/$BJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])') && [[ "$s" =~ SUCCEEDED|FAILED|CANCELLED ]]; do sleep 30; done
echo "batch job $s after $(( $(date +%s) - B0 )) s" > "$OUT/11-batch-wait.txt"
run "gcloud storage cat gs://\$BUCKET/batch/out/*/prediction.results-* | head -3" 12-batch-results.txt bash -c "
gcloud storage cat 'gs://$BUCKET/batch/out/*/prediction.results-*' | head -3; echo; echo \"\$(gcloud storage cat 'gs://$BUCKET/batch/out/*/prediction.results-*' | wc -l | tr -d ' ') predictions written\""

step "Step 10 · Undeploy the endpoint"
DM=$(gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" --format="value(deployedModels[0].id)")
run "gcloud ai endpoints undeploy-model \$ENDPOINT_ID --deployed-model-id <id>" 13-undeploy.txt \
    gcloud ai endpoints undeploy-model "$ENDPOINT_ID" --deployed-model-id "$DM" --region "$REGION" --project "$PROJECT" --quiet
run "gcloud ai endpoints describe \$ENDPOINT_ID   (no deployed models: nothing is billing)" 14-endpoint-empty.txt \
    gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" --format="yaml(displayName,deployedModels)"
run "gcloud ai endpoints predict \$ENDPOINT_ID   (after undeploy)" 15-predict-after.txt \
    gcloud ai endpoints predict "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" --json-request "$WORKDIR/request.json"

step "Step 11 · Teardown"
run "delete the endpoint, the model and the bucket" 16-teardown.txt bash -c "
gcloud ai endpoints delete $ENDPOINT_ID --region $REGION --project $PROJECT --quiet 2>&1 | tail -1
gcloud ai models delete $MODEL_ID --region $REGION --project $PROJECT --quiet 2>&1 | tail -1
gcloud storage rm -r gs://${BUCKET:?} --project $PROJECT 2>&1 | tail -1"
run "verify: endpoints and models named qc-fuel" 17-verify.txt bash -c "
gcloud ai endpoints list --region $REGION --project $PROJECT --filter='displayName~qc-fuel' 2>&1 | tail -1
gcloud ai models list --region $REGION --project $PROJECT --filter='displayName~qc-fuel' 2>&1 | tail -1"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ME="$(gcloud config get-value account 2>/dev/null)"
for f in "$OUT"/*.txt; do sed -i '' -e "s/$NUMBER/PROJECT_NUMBER/g" -e "s/$ME/instructor@example.edu/g" "$f"; done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files"
