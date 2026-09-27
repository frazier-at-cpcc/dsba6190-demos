#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 13 demonstration.

    python3 build-notebook.py

    prep.ipynb   before you start: two training jobs, register ridge, deploy, verify
    demo.ipynb   the demonstration, steps 1 to 11, teardown included

Both run on the Bash kernel. env.sh changes into ~/dsba6190-live-demo-13, so
every file the steps read or write is named relative to that directory: a path
with spaces breaks --json-request and curl -d @file. The batch prediction job
takes about 19 minutes, so step 7 submits it right after version 2 is
registered and step 9 collects it with a polling loop. The notebooks carry step
headings and commands only. The walkthrough is in RUNBOOK.md.
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-13"


def notebook(name, parts):
    cells = []
    for kind, text in parts:
        cell = {"cell_type": kind, "metadata": {}, "id": f"{name}-{len(cells):03d}",
                "source": text.strip("\n").splitlines(keepends=True)}
        if kind == "code":
            cell.update(execution_count=None, outputs=[])
        cells.append(cell)
    nb = {"cells": cells,
          "metadata": {"kernelspec": {"display_name": "Bash", "language": "bash", "name": "bash"},
                       "language_info": {"name": "bash", "codemirror_mode": "shell",
                                         "file_extension": ".sh", "mimetype": "text/x-sh"}},
          "nbformat": 4, "nbformat_minor": 5}
    (HERE / f"{name}.ipynb").write_text(json.dumps(nb, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {name}.ipynb: {len(cells)} cells, "
          f"{sum(c['cell_type'] == 'code' for c in cells)} commands")


def md(text):
    return ("markdown", text)


def sh(text):
    return ("code", text)


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$ENDPOINT_ID" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
API = 'API="https://$REGION-aiplatform.googleapis.com/v1/projects/$PROJECT/locations/$REGION"'
STATE = "python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"state\", \"\"))'"
ENDPOINT_DESCRIBE = ('gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" \\\n'
                     '  --format="yaml(displayName,deployedModels)"')
RESULTS = '"gs://$BUCKET/batch/out/*/prediction.results-*"'

notebook("prep", [
    md("# Session 13 · Before you start"),
    md("## Stage two training jobs, register ridge, deploy\n\n"
       "About 28 minutes. The deployment alone takes about 21 of them."),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## Verify"),
    sh(ENDPOINT_DESCRIBE),
    sh('gcloud ai models list-version "$MODEL_ID" --region "$REGION" --project "$PROJECT"'),
    sh("ls"),
])

notebook("demo", [
    md("# Session 13 · Vertex training, registry, and serving\n\n"
       "Queen City Trip Analytics, a fictional South End, Charlotte company, "
       "predicts each fleet vehicle's fuel economy so a fare quote can carry its fuel cost."),
    LOAD,

    md("## Step 1 · The trainer, packaged for a prebuilt container"),
    sh("tar -tzf qc_fuel_trainer-0.1.tar.gz"),
    sh("tar -xzOf qc_fuel_trainer-0.1.tar.gz qc_fuel_trainer-0.1/trainer/train.py | sed -n '/plain list/,/^mae/p'"),

    md("## Step 2 · Two training jobs, already finished"),
    sh('for j in "$JOB_RIDGE" "$JOB_BOOSTED"; do\n'
       '  gcloud ai custom-jobs describe "$j" --region "$REGION" --project "$PROJECT" \\\n'
       "    --format='value(displayName,state,createTime.date(%H:%M:%S),endTime.date(%H:%M:%S),"
       "jobSpec.workerPoolSpecs[0].machineSpec.machineType)'\n"
       "done"),

    md("## Step 3 · Test error in the log, artifacts in the bucket"),
    sh('for j in "$JOB_RIDGE" "$JOB_BOOSTED"; do\n'
       '  gcloud logging read "resource.type=ml_job AND resource.labels.job_id=${j##*/} AND test_mae_mpg" \\\n'
       "    --project \"$PROJECT\" --limit 1 --format='value(textPayload,jsonPayload.message)'\n"
       "done"),
    sh('gcloud storage ls -l "gs://$BUCKET/models/*/model/"'),

    md("## Step 4 · One model in the registry"),
    sh('gcloud ai models describe "$MODEL_ID" --region "$REGION" --project "$PROJECT" \\\n'
       '  --format="yaml(displayName,versionId,versionAliases,artifactUri,containerSpec.imageUri)"'),

    md("## Step 5 · The endpoint, already deployed"),
    sh(ENDPOINT_DESCRIBE),

    md("## Step 6 · The request, in raw units"),
    sh("cat > request.json <<'JSON'\n"
       '{"instances": [[8, 350, 165, 3693, 11.5, 70, 1], [4, 97, 88, 2130, 14.5, 71, 3], '
       "[4, 140, 86, 2790, 15.6, 82, 1]]}\n"
       "JSON\n"
       "cat request.json"),

    md("## Step 7 · Version 2, then submit the batch job on it"),
    sh('gcloud ai models upload --region "$REGION" --project "$PROJECT" --display-name "qc-fuel-$SUFFIX" \\\n'
       '  --parent-model "projects/$PROJECT/locations/$REGION/models/$MODEL_ID" \\\n'
       '  --artifact-uri "gs://$BUCKET/models/boosted/model" --container-image-uri "$SERVE_IMAGE" \\\n'
       "  --version-aliases=boosted"),
    sh('gcloud ai models list-version "$MODEL_ID" --region "$REGION" --project "$PROJECT" \\\n'
       "  --format=\"table(versionId,versionAliases.list(),versionCreateTime.date('%H:%M:%S'),artifactUri.basename())\""),
    sh("cat > batch.json <<JSON\n"
       '{"displayName": "qc-fuel-batch-$SUFFIX",\n'
       ' "model": "projects/$PROJECT/locations/$REGION/models/$MODEL_ID@boosted",\n'
       ' "inputConfig": {"instancesFormat": "jsonl", "gcsSource": {"uris": ["gs://$BUCKET/batch/input.jsonl"]}},\n'
       ' "outputConfig": {"predictionsFormat": "jsonl", "gcsDestination": {"outputUriPrefix": "gs://$BUCKET/batch/out"}},\n'
       ' "dedicatedResources": {"machineSpec": {"machineType": "n1-standard-2"}, '
       '"startingReplicaCount": 1, "maxReplicaCount": 1}}\n'
       "JSON\n"
       f"{API}\n"
       "date +%s > batch-start.txt\n"
       'curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \\\n'
       "  -H 'Content-Type: application/json' \"$API/batchPredictionJobs\" -d @batch.json \\\n"
       "  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"name\", d)); "
       "print(d.get(\"state\", \"\"))' | tee batch-job.txt"),

    md("## Step 8 · One online prediction, priced"),
    sh('time gcloud ai endpoints predict "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" '
       "--json-request request.json"),
    sh('gcloud ai endpoints predict "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" '
       "--json-request request.json --format=json 2>/dev/null \\\n"
       "  | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"predictions\"]; "
       "[print(f\"vehicle {i+1}: {m:5.1f} mpg  fuel for 20 miles ${20/m*3.20:5.2f}\") "
       "for i,m in enumerate(p)]'"),

    md("## Step 9 · Two cost shapes, then collect the batch job"),
    sh(f"{API}\n"
       "BJ=$(grep -o 'batchPredictionJobs/[0-9]*' batch-job.txt | head -1); echo \"$BJ\"\n"
       'until s=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" "$API/$BJ" '
       f"| {STATE}) \\\n"
       '      && [[ "$s" =~ SUCCEEDED|FAILED|CANCELLED ]]; do\n'
       '  echo "$(date +%H:%M:%S)  $s"; sleep 30\n'
       "done\n"
       'echo "batch job $s after $(( $(date +%s) - $(cat batch-start.txt) )) s"'),
    sh(f"gcloud storage cat {RESULTS} | head -3\n"
       f'echo "$(gcloud storage cat {RESULTS} | wc -l | tr -d \' \') predictions written"'),

    md("## Step 10 · Undeploy the endpoint"),
    sh('DM=$(gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" '
       '--format="value(deployedModels[0].id)"); echo "$DM"'),
    sh('gcloud ai endpoints undeploy-model "${ENDPOINT_ID:?}" --deployed-model-id "${DM:?}" \\\n'
       '  --region "${REGION:?}" --project "${PROJECT:?}" --quiet'),
    sh(ENDPOINT_DESCRIBE),
    sh('gcloud ai endpoints predict "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" '
       "--json-request request.json"),

    md("## Step 11 · Teardown, then verify"),
    sh('gcloud ai endpoints delete "${ENDPOINT_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet\n'
       'gcloud ai models delete "${MODEL_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet'),
    sh('gcloud storage rm -r "gs://${BUCKET:?}" --project "${PROJECT:?}"'),
    sh('gcloud ai endpoints list --region "$REGION" --project "$PROJECT" --filter="displayName~qc-fuel"\n'
       'gcloud ai models list --region "$REGION" --project "$PROJECT" --filter="displayName~qc-fuel"'),
])
