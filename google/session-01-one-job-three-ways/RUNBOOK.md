# Session 1 walkthrough · One nightly job, three ways

This walkthrough follows one nightly job through twelve steps on Compute Engine, Cloud Run jobs,
Cloud Storage and BigQuery, in `us-east1` and the `US` multi-region. Every command below was run end
to end on 27 September 2026, and `capture/` holds the full output of each one. You can read the
walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost less than one cent in compute, plus a few cents of storage
> for the day the file exists. Delete what you create, in the order step 12 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional twelve-person analytics company in South End,
Charlotte. It sells demand and pricing dashboards to ground-transportation fleets. Every night a
fleet customer drops one file of completed trips, 2,000,000 rows across twelve Charlotte
neighborhoods. By morning the company must deliver trips and revenue by pickup zone.

The demonstration runs that one job three ways: on a virtual machine the company manages, as a Cloud
Run job the company only packages, and as one BigQuery query the company only writes. The same shell
script runs on the first two platforms. The answers match to the cent. What differs is what the
company manages, how long each run took, and what each run billed. The comparison measures the
service-model ladder: infrastructure, a managed container runtime, and a serverless query engine.

---

## Before you start

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-01/env.sh
gcloud storage ls -l "gs://$BUCKET/raw/"      # one file, 135,535,057 bytes
```

The script enables four APIs, generates the night of trips from a fixed seed, creates the company's
bucket in `us-east1`, and uploads the file and `job/rollup.sh`. It creates no VM, no job and no
dataset. The upload time depends on your network. Allow five minutes.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Keep the Console open in a second browser tab for step 4.

---

## The sequence

| # | Step |
|---|---|
| 1 | Who and where |
| 2 | Where the project sits |
| 3 | Geography |
| 4 | A bucket, and what cannot change |
| 5 | Last night's file |
| 6 | The job on a virtual machine |
| 7 | The same job on Cloud Run |
| 8 | The same question in BigQuery |
| 9 | Three platforms, one answer |
| 10 | What each run cost |
| 11 | Where cost appears |
| 12 | Teardown |

### Step 1 · Who and where

`gcloud config list`, `gcloud auth list`, then `gcloud projects describe`. The project has a display
name, an ID, `YOUR_PROJECT_ID`, and a number. **What to notice.** The ID never changes, and every
command uses it. Most permission errors come from the wrong account or the wrong project.

### Step 2 · Where the project sits

`gcloud projects get-ancestors` returns the project alone. The demonstration project has no
organization above it. **What to notice.** Policy set on an organization or folder flows down to
every project beneath it. A project with no parent inherits nothing and is governed by nothing.

### Step 3 · Geography

The run listed 43 regions, nine in the United States, and three zones in `us-east1`. **What to
notice.** `us-east1` is in Moncks Corner, South Carolina, the closest region to Charlotte. Latency,
data location and price all follow from this one choice.

### Step 4 · A bucket, and what cannot change

Create a bucket in the Console first, then create the same bucket with `gcloud storage buckets
create`. `buckets describe` shows `location_type: region`. `buckets update --location us` fails with
`unrecognized arguments: --location`. Changing the default class to `NEARLINE` succeeds. **What to
notice.** Location is fixed at creation. The storage class is not. Compare the two creations. Only
the command-line version can be handed to a colleague and repeated exactly, which is the case for
infrastructure as code.

### Step 5 · Last night's file

The bucket holds one object of 135,535,057 bytes, plus `job/rollup.sh`. The script streams the file
with `gcloud storage cat` into an `awk` rollup and writes the result back to the bucket with its own
timing. **What to notice.** The same eight lines run on the VM and on Cloud Run.

### Step 6 · The job on a virtual machine

An `e2-standard-2` VM boots with a startup script that runs the rollup and shuts the machine down.
From create to `TERMINATED`, the run took **104 seconds**. The rollup itself took **7 seconds**. The
disk remains after the machine stops. **What to notice.** The company chose the operating system,
the machine size and the shutdown. Boot time, not work, dominated the run. A stopped VM still bills
for its disk.

### Step 7 · The same job on Cloud Run

A Cloud Run job runs on Google's `google-cloud-cli` image with 2 vCPU and 2 GiB. The execution ran
for **29 seconds** from start to completion, and the rollup inside it for **3**. Nothing remains
running afterwards. **What to notice.** The job has no operating system, no disk and no shutdown
line. The company packaged a command, and Google ran it.

### Step 8 · The same question in BigQuery

`bq load` took **12 seconds** of wall time. The query processed 0.05 GB and billed **51 MB** with
0.1 seconds of slot time. **What to notice.** BigQuery read two of the seven columns. On-demand
pricing bills bytes processed, so the columns a query names determine its cost.

### Step 9 · Three platforms, one answer

Each platform returned twelve rows. The comparison prints `VM and Cloud Run agree` and `VM and
BigQuery agree`. Uptown led with 440,170 trips and $5,200,966.59.

### Step 10 · What each run cost

| Platform | Measured | List price |
|---|---|---|
| Compute Engine | 104 s of `e2-standard-2` | $0.00194 |
| Cloud Run job | 29 s of 2 vCPU, 2 GiB | $0.00116 |
| BigQuery on-demand | 51 MB billed | $0.00030 |

The stopped VM's 10 GB standard disk bills $0.40 a month until it is deleted. **What to notice.**
Every figure is a fraction of a cent, and overhead rather than work dominates each one. The ranking
changes with the workload. Consider which platform wins when the file is 200 GB and the job runs for
an hour.

### Step 11 · Where cost appears

`gcloud billing projects describe` shows the billing account linked to the project, and `gcloud
billing budgets list` shows the project's budget with its threshold rules on actual and forecast
spend. Open the billing reports page in the Console. **What to notice.** A budget sends alerts. It
does not stop spending.

### Step 12 · Teardown

```sh
gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet
gcloud run jobs delete "${JOB:?}" --region "${REGION:?}" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"
gcloud storage rm -r "gs://${BUCKET:?}" "gs://${SCRATCH:?}" --quiet
```

Deleting the instance deletes its boot disk. Every name is written `${NAME:?}`, so an empty variable
refuses to run instead of deleting the wrong thing. The verification cell lists nothing.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `gcloud run jobs create` asks to enable an API | `live-setup.sh` was skipped. Answer yes and wait a minute |
| The VM never reaches `TERMINATED` | The startup script failed before `shutdown`. Read `gcloud compute instances get-serial-port-output "$VM" --zone "$ZONE"` |
| The VM takes longer than three minutes to stop | Continue to step 7 while it finishes |
| `q` prints `Not found: Dataset` | Step 8's `bq mk` was skipped. Run the `bq mk` cell |
| Cloud Run starts slowly | The first execution in a region pulls the image. Wait for it to finish |
| The upload in `live-setup.sh` is slow | The steps do not depend on the file until step 5 |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-trips.py` | Generates the seeded night of Queen City trips |
| `job/rollup.sh` | The nightly rollup that runs on the VM and on Cloud Run |
| `lib.sh` | The `q` helper, shared with the Session 7 demonstration |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and the real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
