# Session 13 walkthrough · Train, register and serve

This walkthrough follows one fuel-economy model through eleven steps on Vertex AI. It uses custom
training on the prebuilt `sklearn-cpu.1-6` container, the Model Registry, one endpoint on an
`n1-standard-2` node, and one batch prediction job, all in `us-central1`. Every command below was
run end to end on 27 September 2026, and `capture/` holds the full output of each one. You can read
the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. At list prices the recorded run cost about 15 cents. The two training jobs ran
> for 5 min 40 s and 4 min 20 s on `e2-standard-4`, about three cents at the managed rate of $0.15
> to $0.20 an hour. The endpoint held one `n1-standard-2` node for about 40 minutes at $0.10 to
> $0.13 an hour. The batch job held a second `n1-standard-2` node for 1,141 seconds, which cost
> three to four cents. The 184,326 bytes of models and the batch files in Cloud Storage cost under
> a cent. The endpoint is the only charge that grows with time. It bills every hour a model stays
> deployed, whether or not anyone requests a prediction. At those rates a node left deployed for a
> month costs about $73 to $95. Undeploy first, then delete what you create, in the order steps 10
> and 11 show.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` trains, registers and deploys, and never deletes anything.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional analytics firm in South End, Charlotte, the same
company as in earlier demonstrations. Its fleet customers want each fare quote to carry the trip's
fuel cost. The firm therefore trains a model that predicts a vehicle's miles per gallon from the
attributes the fleet registers. Fuel is priced at $3.20 a gallon over a 20-mile trip. Both figures
are stated assumptions.

The data is the UCI Auto MPG dataset (Quinlan, 1993), published under CC BY 4.0, in
`sample/auto-mpg.data`. The trainer drops the rows with a missing horsepower and keeps 392 vehicles
with seven attributes each: cylinders, displacement, horsepower, weight, acceleration, model year
and origin.

Two pairs of options compete. Ridge regression and gradient-boosted trees compete on test error. An
endpoint and a batch job compete on the shape of their cost.

---

## Before you start

You need the Google Cloud CLI, signed in to a project with billing enabled, plus `python3` and
`curl`. `live-setup.sh` uses Python's standard library to build the trainer package and the batch
input, so no local Docker is needed. The notebooks need Jupyter with the Bash kernel.

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-13/env.sh
gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --format="yaml(displayName,deployedModels)"
```

The script enables the Vertex AI API, creates a bucket, and uploads the data and the batch input. It
builds the trainer as a source distribution and submits two custom training jobs in parallel. It
then registers the ridge model, creates an endpoint and deploys the model onto one `n1-standard-2`
node. Staging took **27 minutes 42 seconds** on the recorded run. Both training jobs finished within
six minutes of submission. Registering the model, creating the endpoint and deploying the model took
about 21 minutes. The endpoint node bills from deployment until step 10 undeploys it, so start
`demo.ipynb` as soon as staging finishes.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. The LOAD cell sources `env.sh`, which changes into the working directory, so
every later cell reads and writes relative file names.

---

## The sequence

| # | Step |
|---|---|
| 1 | The trainer, packaged for a prebuilt container |
| 2 | Two training jobs, already finished |
| 3 | Test error in the log, artifacts in the bucket |
| 4 | One model in the registry |
| 5 | The endpoint, already deployed |
| 6 | The request, in raw units |
| 7 | Version 2, then submit the batch job on it |
| 8 | One online prediction, priced |
| 9 | Two cost shapes, then collect the batch job |
| 10 | Undeploy the endpoint |
| 11 | Teardown, then verify |

### Step 1 · The trainer, packaged for a prebuilt container

```sh
tar -tzf qc_fuel_trainer-0.1.tar.gz
tar -xzOf qc_fuel_trainer-0.1.tar.gz qc_fuel_trainer-0.1/trainer/train.py | sed -n '/plain list/,/^mae/p'
```

The package holds `setup.py`, `trainer/__init__.py`, `trainer/train.py` and `PKG-INFO`. The excerpt
shows a `ColumnTransformer` inside a `Pipeline`. It scales the six numeric columns and one-hot
encodes origin, and it selects each column by position. **What to notice.** The preprocessing is
saved with the model, so no caller repeats it. The trainer runs as a package on a prebuilt
container, so no local Docker build is needed.

### Step 2 · Two training jobs, already finished

```
qc-fuel-ridge-33351     JOB_STATE_SUCCEEDED  18:22:40  18:28:20  e2-standard-4
qc-fuel-boosted-33351   JOB_STATE_SUCCEEDED  18:22:41  18:27:01  e2-standard-4
```

Ridge took 5 min 40 s and boosted trees 4 min 20 s, each on one `e2-standard-4`. **What to notice.**
The model work covers only 392 rows, so provisioning takes most of each job. Ten minutes of
`e2-standard-4` at the managed rate costs about three cents.

### Step 3 · Test error in the log, artifacts in the bucket

```
model=ridge rows=392 test_mae_mpg=2.52
model=boosted rows=392 test_mae_mpg=2.08

  182117  2026-09-27T18:26:50Z  gs://qc-fuel-33351/models/boosted/model/model.joblib
    2209  2026-09-27T18:27:50Z  gs://qc-fuel-33351/models/ridge/model/model.joblib
```

**What to notice.** Boosted trees err by 2.08 mpg against 2.52 for ridge, in an artifact 82 times
larger. At 25 mpg the 20-mile fuel cost is $2.56, and a 2.52 mpg error can move it by up to 29
cents. Nothing is registered or serving yet.

### Step 4 · One model in the registry

```
artifactUri: gs://qc-fuel-33351/models/ridge/model
containerSpec:
  imageUri: us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest
versionAliases:
- ridge
- default
versionId: '1'
```

**What to notice.** A registered model names an artifact and a serving container. The serving
container is chosen independently of the training container. The registry entry holds no machine.

### Step 5 · The endpoint, already deployed

```sh
gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" \
  --format="yaml(displayName,deployedModels)"
```

The describe shows the ridge model deployed on the endpoint. The staging output ends with `Staged in
27 min 42 s. The ridge model is deployed and billing.` **What to notice.** Deployment took about 21
of those minutes. The node has billed since then, whether or not anyone asks for a prediction.

### Step 6 · The request, in raw units

```
{"instances": [[8, 350, 165, 3693, 11.5, 70, 1], [4, 97, 88, 2130, 14.5, 71, 3], [4, 140, 86, 2790, 15.6, 82, 1]]}
```

Each vehicle carries seven values, in the units the fleet registers them. **What to notice.** The
request needs no hand normalization, because the saved pipeline scales and encodes the values
itself. When preprocessing runs outside the saved model, every caller must repeat it exactly, and
any difference between training and serving is called **training/serving skew**.

### Step 7 · Version 2, then submit the batch job on it

```
VERSION_ID  VERSION_ALIASES  VERSION_CREATE_TIME  ARTIFACT_URI
1           ridge,default    18:28:38             model
2           boosted          18:50:23             model

projects/PROJECT_NUMBER/locations/us-central1/batchPredictionJobs/3803742205500194816
JOB_STATE_PENDING
```

Upload the boosted artifact with `--parent-model` and list the versions. Then write `batch.json` and
submit it with `curl`. Submit the batch job before you move on, because it took 1,141 seconds on the
recorded run. **What to notice.** The default alias stays on version 1. The batch job names version
2 by its alias, `@boosted`, and brings up its own `n1-standard-2` node.

### Step 8 · One online prediction, priced

```
[13.70540020767342, 25.72558817634198, 27.89073869807162]

vehicle 1:  13.7 mpg  fuel for 20 miles $ 4.67
vehicle 2:  25.7 mpg  fuel for 20 miles $ 2.49
vehicle 3:  27.9 mpg  fuel for 20 miles $ 2.29
```

The first cell runs under `time`, so its output ends with the elapsed seconds. The capture does not
include them. **What to notice.** The endpoint answers from version 1, ridge, because that is the
model deployed on it. Registering version 2 changed nothing the endpoint does. The eight-cylinder
vehicle costs about twice as much fuel per trip as either four-cylinder vehicle.

### Step 9 · Two cost shapes, then collect the batch job

Compare the two ways of serving before you collect the batch job:

| | Endpoint | Batch job |
|---|---|---|
| Machine | One `n1-standard-2`, dedicated | One `n1-standard-2`, dedicated |
| Held for | From deployment to step 10, about 40 minutes on the recorded run | 1,141 seconds |
| Work done | Three predictions | 392 predictions |
| Bills while idle | Yes | No, because the job ends |

Then run the collect cell. It polls every 30 seconds and prints the state until the job ends.

```
batch job JOB_STATE_SUCCEEDED after 1141 s
{"instance": [8.0, 350.0, 165.0, 3693.0, 11.5, 70, 1], "prediction": 13.965738016923567}
392 predictions written
```

**What to notice.** The second output row is vehicle 1 from step 8. Boosted trees predict 13.97 mpg
where ridge predicted 13.71. Nightly repricing of a fleet suits a batch job. A dispatcher waiting on
a quote needs an endpoint.

### Step 10 · Undeploy the endpoint

```sh
gcloud ai endpoints undeploy-model "${ENDPOINT_ID:?}" --deployed-model-id "${DM:?}" \
  --region "${REGION:?}" --project "${PROJECT:?}" --quiet
```

The describe that follows shows `displayName: qc-fuel-33351` and no deployed models. The same
prediction as step 8 now fails:

```
ERROR: (gcloud.ai.endpoints.predict) FAILED_PRECONDITION: Endpoint ... misconfigured,
"traffic_split" not set.
```

**What to notice.** Undeploying stops the hourly charge. The empty endpoint remains until it is
deleted. Undeploy at this step even if the batch job is still running, because the batch job uses
its own node.

### Step 11 · Teardown, then verify

```sh
gcloud ai endpoints delete "${ENDPOINT_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet
gcloud ai models delete "${MODEL_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet
gcloud storage rm -r "gs://${BUCKET:?}" --project "${PROJECT:?}"
```

Both list commands print `Listed 0 items.` Every name is written `${NAME:?}`, so an empty variable
refuses to run instead of deleting the wrong thing. **What to notice.** Sort the deletions by what
they stop. Undeploying stopped the hourly charge at step 10. Deleting the bucket stops a storage
charge of cents. Deleting the endpoint and the model only tidies up.

Before you close the notebook, confirm that nothing remains:

- [ ] `gcloud ai endpoints list --region us-central1 --filter="displayName~qc-fuel"` lists nothing
- [ ] `gcloud ai models list --region us-central1 --filter="displayName~qc-fuel"` lists nothing
- [ ] `gcloud storage ls | grep qc-fuel` prints nothing
- [ ] The batch job shows `JOB_STATE_SUCCEEDED`, `FAILED` or `CANCELLED` in the Console

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| The LOAD cell prints `NOT STAGED` | `live-setup.sh` did not finish. Read the end of the `prep.ipynb` output, fix the cause and rerun it |
| `live-setup.sh` stops with `training job ... was not created` or `deploy failed` | The script prints the last 20 lines of the log. A failed run leaves its resources in place, so delete the endpoint, the model and the bucket named with the printed suffix before you rerun it |
| `gcloud ai custom-jobs create --local-package-path` fails while building an image | That option builds a Docker image locally. Use the source distribution that `live-setup.sh` builds, which runs on the prebuilt `sklearn-cpu.1-6` training container with `python-module=trainer.train` |
| Online prediction fails in the prediction container although training succeeded | The container passes each instance as a plain list with no column names. Select columns by position, as `trainer/train.py` does |
| `--json-request` or `curl -d @file` cannot find its file | The path contains spaces. Source `env.sh`, which changes into `~/dsba6190-live-demo-13`, and name files relatively |
| The step 8 prediction fails before step 10 | The deployment did not complete, and the step 5 describe shows no deployed model. Wait for the deployment to finish, or rerun it |
| The batch job has not finished when you reach step 10 | Undeploy at step 10 regardless. Run step 11 after the job ends. The model and the bucket cost under a cent in the meantime |
| The collect cell prints an empty state | The access token expired or `batch-job.txt` is empty. Run `gcloud auth login`, then rerun the cell |
| Credentials expire | Run `gcloud auth login`. The `curl` cells request a fresh token each time |

---

## Files

| Path | What it is |
|---|---|
| `trainer/train.py`, `setup.py` | The trainer: a scikit-learn pipeline that selects columns by position, packaged for the prebuilt container |
| `sample/auto-mpg.data` | The UCI Auto MPG dataset, CC BY 4.0 |
| `live-setup.sh` | Trains both models, registers ridge and deploys it. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and 18 files of real output. The recorder deletes everything through an exit trap |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
