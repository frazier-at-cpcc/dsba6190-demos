# Session 11 live demo · runbook

Build a stream, then break it. One hour, eleven steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: Pub/Sub, three
Dataflow streaming jobs on Apache Beam 2.76.0 in `us-central1`, each on one `e2-standard-2` worker
with Streaming Engine and no external IPs, and BigQuery. Every command below was run, and
`capture/` holds the full output of each one.

**Do not run `capture.sh` in class.** It stages its own topics and jobs and deletes everything
through an exit trap. `live-setup.sh` provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. The basis for its cost is the worker: one
> `e2-standard-2` is 2 vCPU and 8 GB, and at list prices of about $0.069 per streaming vCPU-hour and
> $0.0036 per GB-hour it costs about $0.17 per job-hour. The rehearsal ran three jobs for about 20
> minutes each, one job-hour, or about $0.17. In class the three jobs run from T minus 30 to the end
> of the demonstration, about three hours each, or about $1.50. Streaming Engine is billed separately
> and is not included; Pub/Sub at demo volume sits inside its free 10 GiB a month. Dataflow has no
> free tier, so reproducing the hour on your own account costs the same. A job forgotten for a month
> costs about $120. **Destroy what you create, in the order step 11 shows.**

---

## The scenario · Crown Street Markets

**Crown Street Markets** is fictional: the 40-store Charlotte grocery chain from Session 6. Every
register sale is one Pub/Sub message on `register-events` carrying the store, the lane and the
total, plus two attributes: `event_ts`, when the sale was rung, and `sale_id`, the register's own
identifier. A Dataflow job turns the stream into one-minute sales-by-store windows in BigQuery, and
the store managers' staffing dashboard reads them.

Three things go wrong tonight, and each one is a symptom in the Lab 11 failure-analysis memo. The
Ballantyne store's register, CLT-031, loses its connection in a storm and uploads a sale 30 minutes
late. A register at CLT-007 times out and publishes the same sale twice. A scanner firmware update
at CLT-022 sends a total as the text `"$3.49"`.

Three jobs read the same topic through three subscriptions, so the room watches them disagree.

| Job | Windowing | Reads with |
|---|---|---|
| `crown-baseline` | One-minute fixed windows, no allowed lateness | `timestamp_attribute="event_ts"` |
| `crown-lateness` | The same, with 3,600 s allowed lateness, a late re-fire and accumulating panes | `timestamp_attribute="event_ts"` |
| `crown-dedup` | The same as baseline | `timestamp_attribute="event_ts"`, `id_label="sale_id"` |

Every job routes a record it cannot parse to one shared dead-letter topic with the error attached.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Unbounded data and the two clocks | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Correctness and failure | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Memo workshop, then Lab 11 supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

---

## Before class

```sh
cd "lectures/demos/session-11-build-a-stream-then-break-it"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 30
source ~/dsba6190-live-demo-11/env.sh
gcloud dataflow jobs list --region "$REGION" --status=active --filter="name~crown-.*-$SUFFIX"   # three Running
```

The script enables the Dataflow and Pub/Sub APIs, grants the Dataflow service agent its role and
waits 60 seconds, creates the topic, the three subscriptions, the dead-letter topic and its
subscription, a staging bucket and a dataset, and launches the three jobs. It then blocks twice.
It waits until all three jobs report Running, which took **111 seconds** after submission on the
rehearsal. It then publishes five-sale warm-up bursts until the baseline table exists, which took
**250 seconds**. Allow about seven minutes in all. T minus 30 leaves room for one failed launch.

To cut the in-class cost to about a third, run `prep.ipynb` at the break instead. The 35 minutes
before the demonstration still cover the seven the script needs.

| Symptom | Cause | Fix |
|---|---|---|
| All three jobs fail within a minute of launch, and the job log says the Dataflow service agent lacks access to the worker service account | A freshly enabled Dataflow API launches jobs before its service agent holds its role. This happened on 27 September 2026 | The script creates the service agent, grants `roles/dataflow.serviceAgent`, and waits 60 seconds before launching |
| A job cannot start its worker and reports an external IP address quota error | Each Dataflow worker takes an external IP by default, and three jobs exhaust the project's regional quota | Every launch passes `--no_use_public_ips` |
| Jobs report Running but never read a message | `--no_use_public_ips` needs Private Google Access on the subnet | The script warns when it is off. Enable it on the `default` subnet in `us-central1` |
| Jobs report Running and the baseline table does not exist | Workers start after the job reports Running | Wait. The script keeps publishing warm-up bursts until the table appears |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. Every wait is an until-loop that returns as soon as the rows exist, so no cell
sleeps longer than it needs to. Open the three console links step 2 prints in browser tabs before
the hour starts; steps 4 and 9 use them.

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | The substrate, in ninety seconds | 4 | 30 |
| 2 | Three jobs, started before class | 4 | 31 |
| 3 | A burst of 200 sales, and rows in BigQuery | 6 | 32, 33 |
| 4 | The watermark, in the console | 6 | 34 |
| 5 | A sale rung 30 minutes ago | 7 | 35 |
| 6 | The allowed-lateness job re-fires | 6 | 36 |
| 7 | One sale, published twice | 6 | 37 |
| 8 | A malformed record | 6 | 38 |
| 9 | Lag, backlog, and what to alert on | 5 | 39 |
| 10 | Drain one, cancel another | 6 | 40 |
| 11 | Teardown | 3 | 41 |

Slide 26 is the divider, slide 27 introduces the scenario, and slides 28 and 29 carry the run sheet.
Slides 42 to 47 are the memo workshop. The deck runs to 63 slides.

### Step 1 · The substrate · slide 30 · 4 minutes

```
DATA                STORE_ID  MESSAGE_ID
b'register test 3'  CLT-003   21275702398950733
b'register test 1'  CLT-001   21274643676181478
b'register test 2'  CLT-002   21275728857067390
```

Create a scratch topic and subscription, publish three messages, pull them back. **What to
notice.** They came back 3, 1, 2, and every publish got its own message ID. Step 7 depends on the
second point.

### Step 2 · Three jobs, started before class · slide 31 · 4 minutes

```
crown-dedup-23287     Running  2026-09-27 15:36:22
crown-lateness-23287  Running  2026-09-27 15:36:22
crown-baseline-23287  Running  2026-09-27 15:36:22
jobs running 111 s after submission
first rows 250 s after submission
```

Name the three variants and open the console links the cell prints. **What to notice.** Four
minutes from submission to the first row is why no streaming job starts in front of the room.

### Step 3 · A burst, and rows in BigQuery · slides 32 and 33 · 6 minutes

```
| baseline |   200 | 18298.8 |       1 |
| dedup    |   200 | 18298.8 |       1 |

| 2026-09-27 15:41:00 | CLT-029  |    10 |  788.15 | 1    |
```

200 sales rung at 15:41:33 UTC, $18,298.80, one window in each job. CLT-029 was busiest with 10
sales. **What to notice.** Both jobs agree because nothing has gone wrong yet, and pane `1` is
Beam's on-time firing. Step 6 shows the other value.

### Step 4 · The watermark, in the console · slide 34 · 6 minutes

No capture; this step is live only. Open the baseline job. Walk the job graph from Read to Write
and point at the DeadLetter branch. Open job metrics and show data freshness and system latency.
**What to notice.** Data freshness is the watermark as a number: how far event time trails the
wall clock. When the watermark passes a window's end, the window fires.

### Step 5 · A sale rung 30 minutes ago · slide 35 · 7 minutes

```
published one CLT-031 sale of $412.18 rung at 15:14:28Z, message id 22070542668169862
$ bq query: CLT-031 in the window it was rung, baseline job
```

The baseline query returned no rows. **What to notice.** The sale is gone, the job is Running, and
no error appeared. The dashboard's 15:14 total for Ballantyne is $412.18 short.

### Step 6 · The allowed-lateness job re-fires · slide 36 · 6 minutes

```
| 2026-09-27 15:14:00 | CLT-031  |     1 |  412.18 | 2    |
```

The same sale reached the lateness job, which emitted a late pane for the 15:14 window. **What to
notice.** Pane `2` is Beam's code for a late firing. The dashboard must replace the row for that
store and minute, not append a second one.

### Step 7 · One sale, published twice · slide 37 · 6 minutes

```
published sale S-DUP-1790524027 twice: message ids 22066449219660541 and 22066374354237061
| baseline |     2 |   176.8 |
| dedup    |     1 |    88.4 |
```

**What to notice.** Pub/Sub gave the retry a new message ID, so deduplicating on the message ID
would remove nothing. The dedup job reads with `id_label="sale_id"` and counts one $88.40 sale.
Dataflow deduplicates on that attribute only for a limited time, so the memo still needs an
idempotent sink.

### Step 8 · A malformed record · slide 38 · 6 minutes

```
error: "ValueError: could not convert string to float: '$3.49'"
sale_id: S-BAD-1790524181
```

Three identical dead letters arrived, one from each job, because all three share one dead-letter
topic. **What to notice.** No job stopped. Without the dead-letter branch, streaming Dataflow
retries a failing element indefinitely and the stream stalls behind it: the poison pill from
Hour 2. The until-loop cell may print one copy; the next cell pulls the rest.

### Step 9 · Lag, backlog, and what to alert on · slide 39 · 5 minutes

```
crown-dedup-23287     Running
crown-lateness-23287  Running
crown-baseline-23287  Running
```

Switch to the console: the subscription's oldest unacknowledged message age and undelivered
messages, then the job's system latency and data freshness. **What to notice.** Every fault of the
evening left all three jobs Running. Job state tells the operator nothing; the metrics do.

### Step 10 · Drain one, cancel another · slide 40 · 6 minutes

```sh
gcloud dataflow jobs drain "${BID:?}" --project "$PROJECT" --region "$REGION"
gcloud dataflow jobs cancel "${LID:?}" --project "$PROJECT" --region "$REGION"
```

```
crown-dedup-23287     Running
crown-baseline-23287  Drained
crown-lateness-23287  Cancelled
```

Both reached their final states within four minutes. **What to notice.** Drain stops reading, fires
open windows early and finishes what is in flight. Cancel discards it. Production drains; GSP903
cancels because its project is disposable. That resolves the two stop instructions in the deck.

### Step 11 · Teardown · slide 41 · 3 minutes

```sh
gcloud dataflow jobs cancel "${j:?}" --project "$PROJECT" --region "$REGION"    # each active job
gcloud pubsub subscriptions delete "$s-${SUFFIX:?}" --project "$PROJECT" --quiet  # four, then the scratch one
gcloud pubsub topics delete "${TOPIC:?}" "${DLQ:?}" "${SCRATCH:?}" --project "$PROJECT" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${DATASET:?}"
gcloud storage rm -r "gs://${BUCKET:?}" --project "$PROJECT"
```

Sixty seconds later the dedup job still reported `Cancelling`, and no topic remained. **What to
notice.** A cancelled streaming job takes time to stop; run the verify cell before leaving. Every
name is written `${NAME:?}` so an empty variable refuses to run.

---

## If it fails live

| What happened | Do this |
|---|---|
| `prep.ipynb` is still waiting at 1:30 | Present the capture slides for steps 1 to 3 while it finishes. The jobs were running by 250 seconds on the rehearsal |
| A step 3 or step 7 wait runs past three minutes | Keep teaching from the capture slide. Check the job in the console for a worker error |
| Step 5 shows a row in the baseline job | A warm-up or burst sale from CLT-031 landed in the same two-minute band. Read the pane and the revenue; the late sale is the $412.18 row |
| The dead-letter pull returns nothing for two minutes | Confirm the `dlq-` subscription exists; it must exist before the jobs start |
| A drain runs past five minutes | Present slide 40 and move on. Cancel it at teardown |
| Credentials expire | `gcloud auth login`, or present the capture slides and say the output is recorded |
| The hour runs short | Shorten step 4 to the job graph alone. Never skip step 11 |

---

## Files

| Path | What it is |
|---|---|
| `pipeline/register_stream.py` | The Beam pipeline, three variants selected by `--variant` |
| `pipeline/registers.py` | The register simulator: `burst`, `late`, `duplicate`, `malformed` |
| `live-setup.sh` | Creates the topics, launches the three jobs, waits for first rows. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder, and 19 files of real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
| `RUNBOOK.md`, `Session-11-Live-Demo-Runbook.pdf`, `build-runbook-pdf.py` | This document and its podium PDF |
