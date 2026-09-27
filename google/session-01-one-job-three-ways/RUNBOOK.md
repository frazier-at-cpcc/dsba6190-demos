# Session 1 live demo · runbook

One nightly job, three ways. One hour, twelve steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: Compute Engine,
Cloud Run jobs, Cloud Storage and BigQuery in `us-east1` and the `US` multi-region. Every command
below was run, and `capture/` holds the full output of each one.

**Do not run `capture.sh` in class.** It stages its own bucket and deletes everything through an
exit trap. `live-setup.sh` provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it on your own account costs
> less than one cent in compute, plus a few cents of storage for the day the file exists. **Destroy
> what you create, in the order step 12 shows.**

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is fictional: a twelve-person analytics company in South End,
Charlotte, that sells demand and pricing dashboards to ground-transportation fleets. Every night a
fleet customer drops one file of completed trips, 2,000,000 rows across twelve Charlotte
neighborhoods. By morning the company must deliver trips and revenue by pickup zone.

The hour runs that one job three ways: on a virtual machine the company manages, as a Cloud Run job
it only packages, and as one BigQuery query it only writes. The same shell script runs on the first
two. The answers match to the cent. What differs is what the company manages, how long each run
took, and what it billed. That is the service-model ladder from Hour 1, measured, and it is the kind
of evidence A1 asks students to cite for a different workload.

Introduce the company on the scenario slide in about two minutes, then open each step with one
sentence of what the company is doing. The slide notes carry that sentence.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Orientation | 10 |
| 0:10–0:55 | Concept Block 1 · What cloud computing is for | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Getting hands on the platform | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | A1 briefing, then Lab 1 supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

---

## Before class

```sh
cd "lectures/demos/session-01-one-job-three-ways"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 20
source ~/dsba6190-live-demo-01/env.sh
gcloud storage ls -l "gs://$BUCKET/raw/"      # one file, 135,535,057 bytes
```

The script enables four APIs, generates the night of trips from a fixed seed, creates the company's
bucket in `us-east1`, and uploads the file and `job/rollup.sh`. It creates no VM, no job and no
dataset. Upload time depends on the room's network; allow five minutes.

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. Have the Console open on a second tab for step 4.

| Symptom | Cause | Fix |
|---|---|---|
| `gcloud run jobs create` asks to enable an API | `live-setup.sh` was skipped | Answer yes and wait a minute |
| The VM never reaches `TERMINATED` | The startup script failed before `shutdown` | `gcloud compute instances get-serial-port-output "$VM" --zone "$ZONE"`, then present the capture slide |
| `q` prints `Not found: Dataset` | Step 8's `bq mk` was skipped | Run the `bq mk` cell |

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | Who and where | 4 | 33 |
| 2 | Where the project sits | 3 | 34 |
| 3 | Geography | 3 | 35 |
| 4 | A bucket, and what cannot change | 6 | 36 |
| 5 | Last night's file | 3 | 37 |
| 6 | The job on a virtual machine | 9 | 38 |
| 7 | The same job on Cloud Run | 7 | 39 |
| 8 | The same question in BigQuery | 6 | 40 |
| 9 | Three platforms, one answer | 3 | 41 |
| 10 | What each run cost | 7 | 42 |
| 11 | Where cost appears | 4 | 43 |
| 12 | Teardown | 5 | 44 |

Slide 28 is the divider, slide 29 introduces the scenario, and slides 30 and 31 carry the run
sheet. Slide 32, how you talk to Google Cloud, opens the hour before step 1. The deck runs to 52
slides.

### Step 1 · Who and where · 4 minutes

`gcloud config list`, `gcloud auth list`, then `gcloud projects describe`. The project has a name,
`UNC Charlotte Demo`, an ID, `YOUR_PROJECT_ID`, and a number. **What to notice.** The ID is the
one that never changes and the one every command uses. Nearly every permission error this term is
the wrong account or the wrong project.

### Step 2 · Where the project sits · 3 minutes

`gcloud projects get-ancestors` returns the project alone. The demo project has no organization
above it; the lab projects do. **What to notice.** Policy set on an organization or folder flows
down to every project beneath it. A project with no parent inherits nothing and is governed by
nothing.

### Step 3 · Geography · 3 minutes

43 regions, nine in the United States, three zones in `us-east1`. **What to notice.** `us-east1`
is in Moncks Corner, South Carolina, the closest region to Charlotte. Latency, data location and
price all follow from this one choice.

### Step 4 · A bucket, and what cannot change · 6 minutes

Create a bucket in the Console first, then the same bucket with `gcloud storage buckets create`.
`buckets describe` shows `location_type: region`. `buckets update --location us` fails with
`unrecognized arguments: --location`. Changing the default class to `NEARLINE` succeeds.
**What to notice.** Location is fixed at creation; the storage class is not. Ask which of the two
creations the room could hand to a colleague. Let the silence argue for infrastructure as code.

### Step 5 · Last night's file · 3 minutes

One object, 135,535,057 bytes, and `job/rollup.sh`: `gcloud storage cat` into an `awk` rollup,
written back to the bucket with its own timing. **What to notice.** The same eight lines run on
the VM and on Cloud Run.

### Step 6 · The job on a virtual machine · 9 minutes

An `e2-standard-2` with a startup script that runs the rollup and shuts the machine down. From
create to `TERMINATED`: **104 seconds** on the rehearsal. The rollup itself: **7 seconds**. The
disk is still there after the machine stops. **What to notice.** The company chose the operating
system, the machine size and the shutdown. Boot time, not work, dominated the run. A stopped VM
still bills for its disk.

### Step 7 · The same job on Cloud Run · 7 minutes

A Cloud Run job on Google's `google-cloud-cli` image, 2 vCPU and 2 GiB. The execution ran for
**29 seconds** from start to completion, and the rollup inside it for **3**. Nothing remains
running afterwards. **What to notice.** No operating system, no disk, no shutdown line. The
company packaged a command and Google ran it.

### Step 8 · The same question in BigQuery · 6 minutes

`bq load` took **12 seconds** of wall time. The query processed 0.05 GB and billed **51 MB** with 0.1 seconds of
slot time. **What to notice.** BigQuery read two of the seven columns. On-demand pricing bills bytes
processed, so the columns a query names are its cost.

### Step 9 · Three platforms, one answer · 3 minutes

Twelve rows from each platform. `VM and Cloud Run agree`, `VM and BigQuery agree`. Uptown led with
440,170 trips and $5,200,966.59.

### Step 10 · What each run cost · 7 minutes

| Platform | Measured | List price |
|---|---|---|
| Compute Engine | 104 s of `e2-standard-2` | $0.00194 |
| Cloud Run job | 29 s of 2 vCPU, 2 GiB | $0.00116 |
| BigQuery on-demand | 51 MB billed | $0.00030 |

The stopped VM's 10 GB standard disk bills $0.40 a month until it is deleted. **What to notice.**
Every figure is a fraction of a cent, and every one is dominated by overhead rather than work. Ask
the room which platform wins when the file is 200 GB and runs for an hour. That question is A1.

### Step 11 · Where cost appears · 4 minutes

`gcloud billing projects describe` and the project's budget: $50, with alerts at 50, 90 and 100 per
cent of actual spend and 100 per cent of forecast. Open the billing reports page in the Console.
**What to notice.** A budget alerts. It does not stop spending.

### Step 12 · Teardown · 5 minutes

```sh
gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet
gcloud run jobs delete "${JOB:?}" --region "${REGION:?}" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"
gcloud storage rm -r "gs://${BUCKET:?}" "gs://${SCRATCH:?}" --quiet
```

Deleting the instance deletes its boot disk. Every name is written `${NAME:?}` so an empty variable
refuses to run. The verification cell lists nothing.

---

## If it fails live

| What happened | Do this |
|---|---|
| The upload in `live-setup.sh` is slow | Start it earlier. The hour does not depend on it until step 5 |
| The VM takes longer than three minutes to stop | Present the capture slide and continue to step 7 while it finishes |
| Cloud Run pulls the image slowly | The first execution in a region pulls the image. Keep talking; it finishes |
| The hour runs short | Shorten step 11 to the budget alone. Never skip step 12 |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-trips.py` | The seeded night of Queen City trips |
| `job/rollup.sh` | The nightly rollup that runs on the VM and on Cloud Run |
| `lib.sh` | The `q` helper, shared with Session 7 |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
