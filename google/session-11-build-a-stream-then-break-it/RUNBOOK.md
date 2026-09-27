# Session 11 walkthrough · Build a stream, then break it

This walkthrough follows one register stream through eleven steps on Pub/Sub, Dataflow and BigQuery.
Three Dataflow streaming jobs run on Apache Beam 2.76.0 in `us-central1`, each on one
`e2-standard-2` worker with Streaming Engine and no external IP addresses. Every command below was
run end to end on 27 September 2026, and `capture/` holds the full output of each one. You can read
the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. Each job runs one `e2-standard-2` worker, 2 vCPU and 8 GB. At list prices of
> about $0.069 per streaming vCPU-hour and $0.0036 per GB-hour, one job costs about $0.17 an hour.
> The recorded run held three jobs for about 20 minutes each, one job-hour in total, or about
> $0.17. Following the notebooks takes longer, because the jobs run from `prep.ipynb` until step
> 11. Three jobs for one hour cost about 50 cents. Streaming Engine is billed separately and is not
> included. Pub/Sub at this volume stays inside its free 10 GiB a month. Dataflow has no free tier,
> and a streaming job never finishes on its own. A job left running for a month costs about $120.
> Cancel every job and delete what you create, in the order step 11 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Crown Street Markets

**Crown Street Markets** is a fictional 40-store grocery chain in Charlotte, the same company as in
the Session 6 demonstration. Every register sale is one Pub/Sub message on `register-events`. The
message carries the store, the lane and the total, plus two attributes. The `event_ts` attribute
records when the sale was rung, and `sale_id` is the register's own identifier for the sale. A
Dataflow job turns the stream into one-minute sales-by-store windows in BigQuery, and the store
managers' staffing dashboard reads them.

Three things go wrong in one evening. The Ballantyne store's register, CLT-031, loses its connection
in a storm and uploads a sale 30 minutes late. A register at CLT-007 times out and publishes the
same sale twice. A scanner firmware update at CLT-022 sends a total as the text `"$3.49"`.

Three jobs read the same topic through three subscriptions, so you can watch them disagree.

| Job | Windowing | Reads with |
|---|---|---|
| `crown-baseline` | One-minute fixed windows, no allowed lateness | `timestamp_attribute="event_ts"` |
| `crown-lateness` | The same, with 3,600 s allowed lateness, a late re-fire and accumulating panes | `timestamp_attribute="event_ts"` |
| `crown-dedup` | The same as baseline | `timestamp_attribute="event_ts"`, `id_label="sale_id"` |

Every job routes a record it cannot parse to one shared dead-letter topic with the error attached.

---

## Before you start

You need the Google Cloud CLI with `bq`, signed in to a project with billing enabled. The scripts
run Python 3.11 and Apache Beam through `uv`, so install `uv` first. The notebooks need Jupyter with
the Bash kernel. Workers run without external IP addresses, so the `default` subnet in `us-central1`
needs Private Google Access:

```sh
gcloud compute networks subnets update default --region us-central1 \
  --enable-private-ip-google-access --project YOUR_PROJECT_ID
```

Then stage the demonstration:

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-11/env.sh
gcloud dataflow jobs list --region "$REGION" --status=active --filter="name~crown-.*-$SUFFIX"   # three Running
```

The script enables the Dataflow and Pub/Sub APIs, grants the Dataflow service agent its role and
waits 60 seconds. It creates the topic, the three subscriptions, the dead-letter topic and its
subscription, a staging bucket and a dataset, and launches the three jobs. It then blocks twice.
First it waits until all three jobs report Running, which took **111 seconds** after submission on
the recorded run. Then it publishes five-sale warm-up bursts until the baseline table exists, which
took **250 seconds**. Allow about seven minutes in all. The jobs bill from launch, so start
`demo.ipynb` as soon as staging finishes.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Every wait is an until-loop that returns as soon as the rows exist. Open the
three console links that step 2 prints in browser tabs. Steps 4 and 9 use them.

---

## The sequence

| # | Step |
|---|---|
| 1 | The substrate, in ninety seconds |
| 2 | Three jobs, already running |
| 3 | A burst of 200 sales, and rows in BigQuery |
| 4 | The watermark, in the console |
| 5 | A sale rung 30 minutes ago |
| 6 | The allowed-lateness job re-fires |
| 7 | One sale, published twice |
| 8 | A malformed record |
| 9 | Lag, backlog, and what to alert on |
| 10 | Drain one, cancel another |
| 11 | Teardown |

### Step 1 · The substrate, in ninety seconds

```
DATA                STORE_ID  MESSAGE_ID
b'register test 3'  CLT-003   21275702398950733
b'register test 1'  CLT-001   21274643676181478
b'register test 2'  CLT-002   21275728857067390
```

Create a scratch topic and subscription, publish three messages, and pull them back. **What to
notice.** The messages came back in the order 3, 1, 2, and every publish received its own message
ID. Step 7 depends on the second point.

### Step 2 · Three jobs, already running

```
crown-dedup-23287     Running  2026-09-27 15:36:22
crown-lateness-23287  Running  2026-09-27 15:36:22
crown-baseline-23287  Running  2026-09-27 15:36:22
jobs running 111 s after submission
first rows 250 s after submission
```

The cell lists the three variants and prints a console link for each. **What to notice.** Four
minutes passed between submission and the first row. A streaming job must start well before anyone
needs its output.

### Step 3 · A burst of 200 sales, and rows in BigQuery

```
| baseline |   200 | 18298.8 |       1 |
| dedup    |   200 | 18298.8 |       1 |

| 2026-09-27 15:41:00 | CLT-029  |    10 |  788.15 | 1    |
```

The burst rang 200 sales at 15:41:33 UTC for $18,298.80, in one window in each job. CLT-029 was the
busiest store, with 10 sales. **What to notice.** Both jobs agree because nothing has gone wrong
yet. Pane `1` is Beam's on-time firing. Step 6 shows the other value.

### Step 4 · The watermark, in the console

This step happens in the console, so it has no capture. Open the baseline job. Follow the job graph
from Read to Write, and find the DeadLetter branch. Open the job metrics and read data freshness and
system latency. **What to notice.** Data freshness is the watermark expressed as a number. It
measures how far event time trails the wall clock. When the watermark passes the end of a window,
the window fires.

### Step 5 · A sale rung 30 minutes ago

```
published one CLT-031 sale of $412.18 rung at 15:14:28Z, message id 22070542668169862
$ bq query: CLT-031 in the window it was rung, baseline job
```

The baseline query returned no rows. **What to notice.** The sale is gone, the job is still Running,
and no error appeared. The dashboard's 15:14 total for Ballantyne is $412.18 short.

### Step 6 · The allowed-lateness job re-fires

```
| 2026-09-27 15:14:00 | CLT-031  |     1 |  412.18 | 2    |
```

The same sale reached the lateness job, which emitted a late pane for the 15:14 window. **What to
notice.** Pane `2` is Beam's code for a late firing. The dashboard must replace the row for that
store and minute instead of appending a second row.

### Step 7 · One sale, published twice

```
published sale S-DUP-1790524027 twice: message ids 22066449219660541 and 22066374354237061
| baseline |     2 |   176.8 |
| dedup    |     1 |    88.4 |
```

**What to notice.** Pub/Sub gave the retry a new message ID, so deduplicating on the message ID
would remove nothing. The dedup job reads with `id_label="sale_id"` and counts one $88.40 sale.
Dataflow deduplicates on that attribute only for a limited time, so a production sink still needs to
be idempotent.

### Step 8 · A malformed record

```
error: "ValueError: could not convert string to float: '$3.49'"
sale_id: S-BAD-1790524181
```

Three identical dead letters arrived, one from each job, because all three jobs share one
dead-letter topic. **What to notice.** No job stopped. Without the dead-letter branch, streaming
Dataflow retries a failing element indefinitely, and the stream stalls behind it. A record that
fails every retry and blocks the stream is called a **poison pill**. The until-loop cell can print
one copy. The next cell pulls the rest.

### Step 9 · Lag, backlog, and what to alert on

```
crown-dedup-23287     Running
crown-lateness-23287  Running
crown-baseline-23287  Running
```

Switch to the console. Read the subscription's oldest unacknowledged message age and its undelivered
messages, then the job's system latency and data freshness. **What to notice.** Every fault in this
demonstration left all three jobs Running. Job state told an operator nothing. The metrics did.

### Step 10 · Drain one, cancel another

```sh
gcloud dataflow jobs drain "${BID:?}" --project "$PROJECT" --region "$REGION"
gcloud dataflow jobs cancel "${LID:?}" --project "$PROJECT" --region "$REGION"
```

```
crown-dedup-23287     Running
crown-baseline-23287  Drained
crown-lateness-23287  Cancelled
```

Both jobs reached their final states within four minutes. **What to notice.** A drain stops reading,
fires open windows early and finishes the work in flight. A cancel discards that work. A production
pipeline drains. A cancel suits a disposable project.

### Step 11 · Teardown

```sh
gcloud dataflow jobs cancel "${j:?}" --project "$PROJECT" --region "$REGION"    # each active job
gcloud pubsub subscriptions delete "$s-${SUFFIX:?}" --project "$PROJECT" --quiet  # four, then the scratch one
gcloud pubsub topics delete "${TOPIC:?}" "${DLQ:?}" "${SCRATCH:?}" --project "$PROJECT" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"
gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT"
```

Sixty seconds later the dedup job still reported `Cancelling`, and no topic remained. Every name is
written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong thing. **What
to notice.** A cancelled streaming job takes time to stop. Run the verification cell, and confirm in
the console that no `crown-` job remains Running or Cancelling before you close the notebook. A job
you miss keeps billing.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| All three jobs fail within a minute of launch, and the job log says the Dataflow service agent lacks access to the worker service account | A freshly enabled Dataflow API can launch jobs before its service agent holds its role. `live-setup.sh` grants `roles/dataflow.serviceAgent` and waits 60 seconds. Cancel the failed jobs and rerun it |
| A job cannot start its worker and reports an external IP address quota error | Each worker takes an external address unless the launch passes `--no_use_public_ips`, and three jobs can exceed a project's regional quota. The scripts pass the flag. Check your own quotas on the Console's Quotas page |
| Jobs report Running but never read a message | The subnet lacks Private Google Access. Enable it with the command in Before you start |
| Jobs report Running and the baseline table does not exist | Workers start after the job reports Running. Wait while `live-setup.sh` publishes warm-up bursts until the table appears |
| A step 3 or step 7 wait runs past three minutes | Open the job in the console and read the worker logs for an error |
| Step 5 shows a row in the baseline job | A warm-up or burst sale from CLT-031 landed in the same two-minute band. Read the pane and the revenue. The late sale is the $412.18 row |
| The dead-letter pull returns nothing for two minutes | Confirm that the `dlq-` subscription exists. It must exist before the jobs start |
| A drain runs past five minutes | Continue with the steps, and cancel the job at teardown |
| `capture.sh` stops at step 5 with `date: invalid option` | The recorder uses BSD `date` syntax. Follow the notebooks instead |
| Credentials expire | Run `gcloud auth login` and rerun the cell |

---

## Files

| Path | What it is |
|---|---|
| `pipeline/register_stream.py` | The Beam pipeline, three variants selected by `--variant` |
| `pipeline/registers.py` | The register simulator: `burst`, `late`, `duplicate`, `malformed` |
| `live-setup.sh` | Creates the topics, launches the three jobs and waits for first rows. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder, and 19 files of real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
