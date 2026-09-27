# Session 13 live demo · runbook

Train, register, and serve on Vertex AI. One hour, eleven steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: Vertex AI custom
training on the prebuilt `sklearn-cpu.1-6` container, the Model Registry, one endpoint on an
`n1-standard-2` node, and one batch prediction job, all in `us-central1`. Every command below was
run, and `capture/` holds the full output of each one.

**Do not run `capture.sh` in class.** It stages its own copy of everything and deletes it through an
exit trap. `live-setup.sh` trains, registers and deploys, and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it straight through on your own
> account costs about 15 cents: two training jobs of 5 min 40 s and 4 min 20 s on
> `e2-standard-4`, about three cents at the managed rate of $0.15 to $0.20 an hour; one endpoint
> node on `n1-standard-2` for about 40 minutes at $0.10 to $0.13 an hour; one batch job holding a
> second `n1-standard-2` node for 1,141 seconds, three to four cents; and 184,326 bytes of models plus
> the batch files in Cloud Storage, under a cent. In class the endpoint is deployed before the room
> arrives and bills until step 10, about three and a quarter node-hours, so the evening costs about
> 40 to 50 cents. The endpoint is the only line that grows with time. **Destroy what you create,
> undeploying first.**

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is fictional: the South End analytics firm from Sessions 7 and 8. Its
fleet customers want each fare quote to carry the trip's fuel cost, so the firm trains a model that
predicts a vehicle's miles per gallon from the attributes the fleet registers. Fuel is priced at
$3.20 a gallon over a 20-mile trip. Both figures are stated assumptions.

The data is the UCI Auto MPG dataset (Quinlan, 1993), published under CC BY 4.0, in
`sample/auto-mpg.data`. The trainer drops the rows with a missing horsepower and keeps 392
vehicles with seven attributes each: cylinders, displacement, horsepower, weight, acceleration,
model year and origin.

Two candidate models answer two questions. Ridge regression and gradient-boosted trees compete on
test error. An endpoint and a batch job compete on cost shape.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Training at scale | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Serving, and what hardware buys, with the published scaling figures | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Lab 13 and Badge 5, supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

---

## Before class

```sh
cd "lectures/demos/session-13-vertex-train-register-serve"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 60
source ~/dsba6190-live-demo-13/env.sh
gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --format="yaml(displayName,deployedModels)"
```

The script enables the Vertex AI API, creates a bucket, uploads the data and the batch input, builds
the trainer as a source distribution, and submits two custom training jobs in parallel. It then
registers the ridge model, creates an endpoint and deploys the model onto one `n1-standard-2` node.
It took **27 minutes 42 seconds** on the rehearsal, and the deployment was most of it.

| When | What happens | Rehearsal |
|---|---|---|
| T minus 60 | Run `live-setup.sh` or the first cell of `prep.ipynb` | |
| T minus 59 | Bucket, data and trainer package staged; both training jobs submitted | Under a minute |
| T minus 54 | Both training jobs succeed | Ridge 5 min 40 s, boosted 4 min 20 s |
| T minus 54 to T minus 32 | Ridge registered, endpoint created, model deployed | About 21 minutes |
| T minus 32 | `env.sh` written. Source it and run the Verify cells | Staged in 27 min 42 s |
| T minus 5 | Open `demo.ipynb` and run the LOAD cell | |

The script prints `deploying (about 10 minutes)`. The rehearsal took about 21. Do not start it
later than T minus 45.

| Symptom | Cause | Fix |
|---|---|---|
| `gcloud ai custom-jobs create --local-package-path` fails on the instructor's Mac | That path builds a Docker image locally | The trainer ships as a source distribution that `live-setup.sh` builds with Python's `tarfile`, and runs on the prebuilt `sklearn-cpu.1-6` training container with `python-module=trainer.train`. No local Docker is needed |
| Online prediction fails in the prediction container although training succeeded | A pipeline that selects columns by name receives plain lists with no names | The trainer selects columns by position. Keep it that way |
| `--json-request` or `curl -d @file` cannot find its file | The repository path contains spaces | `env.sh` changes into `~/dsba6190-live-demo-13`, and every command names its files relatively |
| The batch job is still running when the hour ends | Batch prediction took 1,141 seconds, about 19 minutes, on the rehearsal | Step 7 submits it right after version 2 is registered, and step 9 collects it |
| The endpoint is not ready at the start of class | Deployment took about 21 minutes on the rehearsal | `live-setup.sh` deploys before class. The endpoint bills from then until step 10 |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. The LOAD cell sources `env.sh`, which changes into the working directory, so
every later cell reads and writes relative file names.

---

## The sequence

| # | Step | Minutes | Clock | Slide |
|---|---|---|---|---|
| 1 | The trainer, packaged for a prebuilt container | 5 | 1:30 | 35 |
| 2 | Two training jobs, already finished | 4 | 1:35 | 36 |
| 3 | Test error in the log, artifacts in the bucket | 5 | 1:39 | 37 |
| 4 | One model in the registry | 3 | 1:44 | 38 |
| 5 | The endpoint, deployed before class | 3 | 1:47 | 39 |
| 6 | The request, in raw units | 3 | 1:50 | 40 |
| 7 | Version 2, then submit the batch job on it | 5 | 1:53 | 41 |
| 8 | One online prediction, priced | 8 | 1:58 | 42 |
| 9 | Two cost shapes, then collect the batch job | 12 | 2:06 | 43 |
| 10 | Undeploy, in front of the room | 6 | 2:18 | 44 |
| 11 | Teardown, then verify | 6 | 2:24 | 45 |

Slide 31 is the divider, slide 32 introduces Queen City Trip Analytics, and slides 33 and 34 carry
the run sheet. The published-figures segment in Concept Block 2 is slide 29, with its chart on slide
30. The Lab 13 scaffolding follows on slides 46 to 51. The deck runs to 56 slides.

### Step 1 · The trainer · 5 minutes

```sh
tar -tzf qc_fuel_trainer-0.1.tar.gz
tar -xzOf qc_fuel_trainer-0.1.tar.gz qc_fuel_trainer-0.1/trainer/train.py | sed -n '/plain list/,/^mae/p'
```

The package holds `setup.py`, `trainer/__init__.py`, `trainer/train.py` and `PKG-INFO`. The
excerpt shows a `ColumnTransformer` that scales the six numeric columns and one-hot encodes origin,
selected by position, inside a `Pipeline`. **What to notice.** The preprocessing is saved with the
model, so no caller repeats it. A local Docker build failed on the rehearsal machine, which is why
the trainer is a package on a prebuilt container.

### Step 2 · Two training jobs, already finished · 4 minutes

```
qc-fuel-ridge-33351     JOB_STATE_SUCCEEDED  18:22:40  18:28:20  e2-standard-4
qc-fuel-boosted-33351   JOB_STATE_SUCCEEDED  18:22:41  18:27:01  e2-standard-4
```

Ridge took 5 min 40 s and boosted trees 4 min 20 s, each on one `e2-standard-4`. **What to
notice.** The model work is 392 rows, so most of each job is provisioning. That overhead is the gap
Lab 13 asks students to measure between a local `docker run` and a managed job. Ten minutes of
`e2-standard-4` at the managed rate is about three cents.

### Step 3 · Test error and artifacts · 5 minutes

```
model=ridge rows=392 test_mae_mpg=2.52
model=boosted rows=392 test_mae_mpg=2.08

  182117  2026-09-27T18:26:50Z  gs://qc-fuel-33351/models/boosted/model/model.joblib
    2209  2026-09-27T18:27:50Z  gs://qc-fuel-33351/models/ridge/model/model.joblib
```

**What to notice.** Boosted trees err by 2.08 mpg against 2.52 for ridge, in an artifact 82 times
larger. At 25 mpg the 20-mile fuel cost is $2.56, and a 2.52 mpg error can move it by up to 29
cents. Nothing is registered or serving yet.

### Step 4 · One model in the registry · 3 minutes

```
artifactUri: gs://qc-fuel-33351/models/ridge/model
containerSpec:
  imageUri: us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest
versionAliases:
- ridge
- default
versionId: '1'
```

**What to notice.** A registered model names an artifact and a serving container, chosen
independently of the training container. Lab 13 makes that choice by hand for TensorFlow. The
registry entry holds no machine.

### Step 5 · The endpoint, deployed before class · 3 minutes

```sh
gcloud ai endpoints describe "$ENDPOINT_ID" --region "$REGION" --project "$PROJECT" \
  --format="yaml(displayName,deployedModels)"
```

The describe shows the ridge model deployed on the endpoint. The slide carries the staging summary:
`Staged in 27 min 42 s. The ridge model is deployed and billing.` **What to notice.** Deployment
took about 21 of those minutes, and the node has billed since before class whether or not anyone
asks for a prediction.

### Step 6 · The request, in raw units · 3 minutes

```
{"instances": [[8, 350, 165, 3693, 11.5, 70, 1], [4, 97, 88, 2130, 14.5, 71, 3], [4, 140, 86, 2790, 15.6, 82, 1]]}
```

Seven values per vehicle, in the units the fleet registers them. **What to notice.** Lab 13's Task 4
payload carries nine values, normalized by hand, because that model's preprocessing ran outside the
saved model. Put the two side by side. That is training/serving skew and its fix.

### Step 7 · Version 2, then the batch job · 5 minutes

```
VERSION_ID  VERSION_ALIASES  VERSION_CREATE_TIME  ARTIFACT_URI
1           ridge,default    18:28:38             model
2           boosted          18:50:23             model

projects/PROJECT_NUMBER/locations/us-central1/batchPredictionJobs/3803742205500194816
JOB_STATE_PENDING
```

Upload the boosted artifact with `--parent-model`, list the versions, then write `batch.json` and
submit it with `curl`. **Submit the batch job before moving on.** It took 1,141 seconds on the
rehearsal. **What to notice.** The default alias stays on version 1. The batch job names version 2
by its alias, `@boosted`, and brings up its own `n1-standard-2` node.

### Step 8 · One online prediction, priced · 8 minutes

```
[13.70540020767342, 25.72558817634198, 27.89073869807162]

vehicle 1:  13.7 mpg  fuel for 20 miles $ 4.67
vehicle 2:  25.7 mpg  fuel for 20 miles $ 2.49
vehicle 3:  27.9 mpg  fuel for 20 miles $ 2.29
```

The first cell runs under `time`. Read the elapsed seconds aloud. The rehearsal did not record
them. **What to notice.** The endpoint answers from version 1, ridge, because that is the model
deployed on it. Registering version 2 changed nothing the endpoint does. The eight-cylinder vehicle
costs about twice as much fuel per trip as either four-cylinder vehicle.

### Step 9 · Two cost shapes, then collect the batch job · 12 minutes

Spend the first eight minutes on the arithmetic, on the board:

| | Endpoint | Batch job |
|---|---|---|
| Machine | One `n1-standard-2`, dedicated | One `n1-standard-2`, dedicated |
| Held for | Before class to step 10, about 3.25 hours | 1,141 seconds |
| Work done | Three predictions | 392 predictions |
| Bills while idle | Yes | No. It ends |

Then run the collect cell. It polls every 30 seconds and prints the state until the job ends.

```
batch job JOB_STATE_SUCCEEDED after 1141 s
{"instance": [8.0, 350.0, 165.0, 3693.0, 11.5, 70, 1], "prediction": 13.965738016923567}
392 predictions written
```

**What to notice.** The second output row is vehicle 1 from step 8. Boosted trees predict 13.97 mpg
where ridge predicted 13.71. Nightly repricing of a fleet is a batch job. A dispatcher waiting on a
quote needs an endpoint.

### Step 10 · Undeploy, in front of the room · 6 minutes

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
deleted. Say why before running the cell, and do it visibly.

### Step 11 · Teardown, then verify · 6 minutes

```sh
gcloud ai endpoints delete "${ENDPOINT_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet
gcloud ai models delete "${MODEL_ID:?}" --region "${REGION:?}" --project "${PROJECT:?}" --quiet
gcloud storage rm -r "gs://${BUCKET:?}" --project "${PROJECT:?}"
```

Both list commands print `Listed 0 items.` **What to notice.** Sort the deletions by what they
stop. Undeploying stopped the hourly charge at step 10. Deleting the bucket stops storage of cents.
Deleting the endpoint and the model only tidies up. Lab 13's reflection asks for exactly this
classification. Every name is written `${NAME:?}` so an empty variable refuses to run.

### After class

- [ ] `gcloud ai endpoints list --region us-central1 --filter="displayName~qc-fuel"` lists nothing
- [ ] `gcloud ai models list --region us-central1 --filter="displayName~qc-fuel"` lists nothing
- [ ] `gcloud storage ls | grep qc-fuel` prints nothing
- [ ] The batch job shows `JOB_STATE_SUCCEEDED`, `FAILED` or `CANCELLED` in the Console

---

## If it fails live

| What happened | Do this |
|---|---|
| The LOAD cell prints `NOT STAGED` | `live-setup.sh` did not finish. Read the end of the `prep.ipynb` output. After T minus 30 there is no time to restage: present slides 35 to 45 and say the output is recorded |
| `live-setup.sh` stops with `training job ... was not created` or `deploy failed` | It prints the last 20 lines of the log. Before T minus 45, fix and rerun. Later, present the capture slides and delete the endpoint, the model and the bucket named with the printed suffix after class |
| The step 8 prediction fails before step 10 | The deployment did not complete. The step 5 describe shows no deployed model. Present slide 42 |
| The batch job has not finished at 2:18 | Undeploy at step 10 regardless. Present slide 43, and run step 11 after the job ends. The model and the bucket bill nothing meaningful meanwhile |
| The collect cell prints an empty state | The access token expired or `batch-job.txt` is empty. Run `gcloud auth login`, then rerun the cell |
| Credentials expire | `gcloud auth login`. The `curl` cells request a fresh token each time |
| The hour runs short | Shorten step 9's arithmetic. Never skip step 10 |

---

## Files

| Path | What it is |
|---|---|
| `trainer/train.py`, `setup.py` | The trainer: a scikit-learn pipeline that selects columns by position, packaged for the prebuilt container |
| `sample/auto-mpg.data` | The UCI Auto MPG dataset, CC BY 4.0 |
| `live-setup.sh` | Trains both models, registers ridge, deploys it. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and 18 files of real output. The recorder deletes everything through an exit trap |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
| `RUNBOOK.md`, `Session-13-Live-Demo-Runbook.pdf`, `build-runbook-pdf.py` | This document and its podium PDF |
