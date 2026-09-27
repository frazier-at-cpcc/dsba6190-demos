# Session 10 live demo · runbook

Read a plan, find the skew. One hour, eleven steps, 1:30 to 2:30, taught on Zoom.

Captured end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: Serverless for
Apache Spark runtime 2.2, which ran Spark 3.5.3 on Java 17, and BigQuery. `capture/` holds the full
output of every command, and `plan/` holds the four physical plans the job wrote. `live-setup.sh`,
`lib.sh` and the two notebooks are derived from `capture.sh` and have not yet run against the
project. **Run `prep.ipynb` and `demo.ipynb` once, end to end, before 22 October.**

**Do not run `capture.sh` in class.** It stages its own bucket and dataset and deletes both through
an exit trap. `live-setup.sh` provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it on your own account costs
> about 20 cents. **Basis.** Serverless for Apache Spark bills Data Compute Units per second with a
> one-minute minimum, at $0.060 per DCU-hour on the standard tier. Each vCPU counts as 0.6 DCU and
> each gigabyte of memory as 0.1 DCU. Every batch here runs a driver and two executors of four
> vCPU and about 13 GB each, which is roughly 11 DCU, for about three minutes: under 4 cents a
> batch, five batches. Shuffle storage and the quarter-gigabyte of Cloud Storage are fractions of a
> cent. BigQuery loads are free, and the queries process about 1 GB in total, inside the free
> tebibyte each month and $0.006 at $6.25 per TiB beyond it. **Destroy what you create.**

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is fictional: the South End, Charlotte analytics firm from Sessions 7
and 8. It bills its fleet customers every month by joining a year of trips, **30,000,000 rows**, to
its accounts dimension, **5,001 rows**, and summing fares by account tier and month.

Street hails carry the account `WALKUP`, which is never invoiced and holds **60 per cent** of the
trips. It is a real value, not a null, so the join's `isnotnull` filter keeps it, and every
`WALKUP` trip hashes to the same partition. That one key is the skew. The job generates its own data
from fixed seeds, so every number below reproduces.

`jobs/billing.py` runs in five modes. `generate` writes the data. `baseline`, `broadcast`, `salted`
and `aqe` run the same join four ways, and each writes its physical plan to `plans/<mode>/` and its
result to `out/<mode>/`. The job uses only built-in DataFrame functions, so no Python function is
serialized to the executors.

---

## How the hour fits the session clock

Session 10 runs the Zoom variant of the course clock. The breakout rooms need a hard start, so the
lab slot holds at 2:30.

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Midterm debrief, which replaces the retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · How Spark executes | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Clusters, serverless, and the choice | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Breakout rooms: start the Lab 10a cluster, then the A9 workshop while it builds | 25 |
| 2:55–3:00 | Wrap, in the main room | 5 |

---

## Before class

```sh
cd "lectures/demos/session-10-read-a-plan-find-the-skew"
./live-setup.sh YOUR_PROJECT_ID   # or prep.ipynb
source ~/dsba6190-live-demo-10/env.sh
gcloud storage du -s "$BASE/data/trips" # 243 MB
```

The script enables the Dataproc API, confirms Private Google Access on the `default` subnet in
`us-central1`, creates the bucket, uploads `billing.py`, runs the `generate` batch, and loads
`trips` and `accounts` into a new BigQuery dataset for steps 4 and 8. It runs none of the four
variants. On the rehearsal the `generate` batch took **152 seconds**, so expect the script to take
four to five minutes.

`env.sh` exports every name the notebook uses and sources `lib.sh`, which defines the helpers:
`submit` sends a batch with `--async`, `waitfor` polls it with an until-loop, `planof` prints the
plan a variant wrote, `evlog` prints its stage table, `biggest` prints the largest task in each
shuffle-reading stage, `finalplan` prints the plan adaptive execution actually ran, `apptime`
prints how long the Spark application ran, and `bqq` runs a BigQuery query with the cache off and
prints slot time and bytes processed. Every batch carries the properties `capture.sh` used: runtime
2.2, `spark.eventLog.compress=false`, dynamic allocation off, two executors of four cores, and 200
shuffle partitions.

| Symptom | Cause | Fix |
|---|---|---|
| A batch fails within seconds with `Insufficient 'CPUS_ALL_REGIONS' quota` | Each batch holds 12 vCPUs against a project limit of 32 across all regions, and anything else running in the project, including Vertex training jobs, counts against it. The rehearsal failed this way when three batches overlapped | `submit` now waits for the previous batch to finish, and prints that it is waiting. Talk through the plan while it waits. Stop other workloads before class |
| A local `pyspark` shell fails with pickling errors | The laptop runs Python 3.14, which the local PySpark does not support | Nothing in the hour starts Spark on the laptop. The job writes its own plan, and it uses no Python UDF, so nothing is pickled |
| `stages.py` fails with a `UnicodeDecodeError` or a JSON error | The runtime writes zstd-compressed event logs by default | Every batch sets `spark.eventLog.compress=false`. Do not remove it from `COMMON` in `lib.sh` |
| `python3: can't open file '/Users/.../Curriculum'` | The repository path contains spaces | `live-setup.sh` copies `stages.py` and `lib.sh` to `~/dsba6190-live-demo-10`, and `env.sh` changes into it. `capture.sh` quotes every path |
| A batch fails within a minute of submission with a network error | The subnet has no Private Google Access, and a serverless batch has no external IP | `live-setup.sh` checks the `default` subnet and enables it |
| `evlog` prints `no finished event log ... yet` | The batch is still running, so its log is still `.inprogress` | Run `waitfor` for that variant first |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. On Zoom, share the notebook window rather than the whole screen, and zoom one step
further than feels necessary, because the stage tables are dense.

---

## Why the batches are asynchronous

Each Spark variant took 164 to 213 seconds from submission to finish. Four of them run
synchronously would spend a quarter of the hour waiting. Instead, each batch is submitted with
`--async` one step before it is needed and collected later by `waitfor`, which polls every ten
seconds. At most one batch runs at a time, so the demonstration never competes with itself for CPU
quota.

| Batch | Submitted | About ready | Needed |
|---|---|---|---|
| `baseline` | step 1, 0:00 | 0:04 | step 2, 0:05 |
| `broadcast` | step 2, 0:05 | 0:08 | step 5, 0:25 |
| `salted` | step 3, 0:12 | 0:15 | step 6, 0:32 |
| `aqe` | step 4, 0:20 | 0:23 | step 7, 0:38 |

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | The billing job, and the first batch submitted | 5 | 31 |
| 2 | Read the plan | 7 | 32 |
| 3 | The stage table, and the straggler | 8 | 33 |
| 4 | The cause, in the data | 5 | 34 |
| 5 | Broadcast: the join shuffle is gone | 7 | 35 |
| 6 | Salted: one key becomes thirty-two | 6 | 36 |
| 7 | Adaptive execution: coalesced, not split | 7 | 37 |
| 8 | The same join in BigQuery | 5 | 38 |
| 9 | Four variants, one answer | 3 | 39 |
| 10 | Annotate the plan together | 5 | 40 |
| 11 | Teardown | 2 | 41 |

Slide 27 is the divider, slide 28 introduces the scenario, and slides 29 and 30 carry the run
sheet. Slide 15, in Hour 1, shows the full plan tree that step 2 reads. Slides 44 to 49 are the A9
workshop and slides 53 and 54 scaffold the Lab 10 annotation. The deck runs to 57 slides.

### Step 1 · The billing job, and the first batch submitted · 5 minutes

```sh
submit baseline baseline "$OFF"
```

Submit first, then talk. `$OFF` switches off adaptive execution and automatic broadcast so the
baseline shows the raw plan. Show the data sizes, **242,555,519 bytes** of trips against **27,972**
of accounts, and the join in `billing.py`. Ask the room to classify each transformation: the read
and the select are narrow, and the join and the `groupBy` are wide. **What to notice.** Nothing in
the code or the sizes shows the skew.

### Step 2 · Read the plan · 7 minutes

```sh
waitfor baseline
planof baseline | head -17
submit broadcast broadcast "$OFF"
```

The baseline took **213 seconds** and returned 48 rows. Read the tree bottom up: two `Scan parquet`
leaves, a `Filter isnotnull` beside each, `Exchange (4)` and `Exchange (9)` repartitioning both
sides by `hashpartitioning(account_id, 200)`, a `SortMergeJoin`, and `Exchange (14)` for the
aggregate. **What to notice.** The plan names the key and the partition count. It cannot show how
rows spread across keys.

### Step 3 · The stage table, and the straggler · 8 minutes

```sh
submit salted salted "$OFF"
evlog baseline
biggest baseline
```

| Stage | Tasks | Median | Max | Max / median | Shuffle read |
|---|---|---|---|---|---|
| 5, the join | 200 | 0.4 s | **16.9 s** | **43.5** | 377.8 MB |
| 9, the join again | 200 | 0.2 s | 16.1 s | 65.5 | 169.6 MB |

One task in stage 5 read **206.2 MB and 18,058,073 records**. Stage 9 is the job's `count()`
recomputing the join because nothing was cached, and it reads less because `fare` is pruned. **What
to notice.** The max-to-median ratio is the number, and the recomputed join is a cache candidate for
the annotation.

### Step 4 · The cause, in the data · 5 minutes

```sh
submit aqe aqe "$AQE_ON"
bqq "SELECT account_id, COUNT(*) AS trips, ... GROUP BY 1 ORDER BY 2 DESC LIMIT 5"
```

`WALKUP` holds **17,997,932 trips, a share of 0.5999**. The next largest account holds 2,597.
**What to notice.** Cause meets symptom: the 18,058,073 records in the largest task are `WALKUP`
plus the few ordinary accounts that hash to the same partition.

### Step 5 · Broadcast: the join shuffle is gone · 7 minutes

```sh
waitfor broadcast
planof broadcast | sed -n '2,10p'
evlog broadcast
```

`BroadcastExchange (7)` and `BroadcastHashJoin Inner BuildRight (8)` replace the two join
Exchanges. Only `Exchange (11)`, after the join, remains. The only 200-task stage left reads 0.0 MB
with a maximum task of 2.8 s. Wall clock **164 seconds** against 213. **What to notice.** Broadcast
needs one side small enough to copy to every executor. Here it is 5,001 rows.

### Step 6 · Salted: one key becomes thirty-two · 6 minutes

```sh
waitfor salted
planof salted | grep -A2 -E '^\((3|5|10)\) (Project|Exchange|Generate)'
evlog salted
biggest salted
```

The plan adds `cast((rand(3) * 32.0) as int) AS salt`, an `explode` on the accounts side, and
`hashpartitioning(account_id, salt, 200)`. The join stage's maximum falls to **3.1 s** and its ratio
to **8.8**. The largest task reads **7.8 MB**. The shuffle grows to **420.3 MB** because the
accounts are copied 32 times. Wall clock **165 seconds**. **What to notice.** Salting works when
neither side is small, and it costs code someone must maintain.

### Step 7 · Adaptive execution: coalesced, not split · 7 minutes

```sh
waitfor aqe
planof aqe | grep -E '^AdaptiveSparkPlan|isFinalPlan'
finalplan aqe | grep -E 'AQEShuffleRead|SortMergeJoin'
evlog aqe
biggest aqe
```

The printed plan says `isFinalPlan=false`. The final plan from the event log shows
`AQEShuffleRead coalesced` on every shuffle and no skew split. The join ran as **5 tasks** with a
median of 9.0 s and a maximum of **20.0 s**, a ratio of **2.2**. The largest task still read
**206.2 MB**, which is below the default `skewedPartitionThresholdInBytes` of 256 MB, so adaptive
execution never treated it as skewed. Wall clock **169 seconds**. **Say plainly** that the ratio
improved because the median rose, and that the straggler got longer. Adaptive execution is not a
substitute for knowing the data.

### Step 8 · The same join in BigQuery · 5 minutes

```sh
bqq "SELECT a.tier, DATE_TRUNC(t.pickup_date, MONTH) AS month, COUNT(*) AS trips, ... JOIN ..."
```

**1.4 slot-seconds, 686.7 MB processed, 4 stages**, and no batch to start. **What to notice.** If
it fits in SQL, use SQL. Ask which version the billing team should maintain.

### Step 9 · Four variants, one answer · 3 minutes

Every variant returns **48 rows and 1.14017810626E9** in revenue, which is $1,140,178,106.26.
`apptime` shows the Spark applications ran **111.9, 72.7, 78.9 and 80.7 seconds** against wall
clocks of 213, 164, 165 and 169. **What to notice.** Between 86 and 101 seconds of every batch was
provisioning and shutdown. That is the serverless startup figure A9 asks about, measured.

### Step 10 · Annotate the plan together · 5 minutes

```sh
planof baseline > skewed-plan.txt
nl -ba -w2 -s '  ' skewed-plan.txt | sed -n '6,16p'
```

This is the plan Lab 10's annotation supplies, and `plan/skewed-plan.txt` is the copy students
receive. Write the first two annotations together. Lines 8 and 13 are Exchanges, shuffle boundaries
on `account_id` into 200 partitions. Line 6 is the sort-merge join that inherits `WALKUP`'s skew.
Leave the narrow operators, the cache candidate, the driver and the executor configuration to
students.

### Step 11 · Teardown · 2 minutes

```sh
gcloud storage rm -r "gs://${BUCKET:?}"
bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"
gcloud dataproc batches list --region "$REGION" --filter="state=RUNNING"
```

A finished batch releases its own machines. The bucket and the dataset hold the data, the plans,
the event logs and four result tables. The rehearsal listed **0** running batches afterwards. Every
name is written `${NAME:?}` so an empty variable refuses to run.

---

## If it fails live

| What happened | Do this |
|---|---|
| `waitfor` is still polling when its step arrives | Present the step's capture slide and move on. Collect the batch at the next step |
| A batch ends `FAILED` | Present the capture slide. Resubmit with `submit <name> <mode> "$OFF"` only if the hour has room |
| `submit` fails on CPU quota | A previous batch is still running. Run `waitfor` on it, then submit again |
| The Zoom connection drops | The capture slides carry every figure. Rejoin and resume from the deck |
| The hour runs short | Merge steps 8 and 9 and cut step 10 to the first annotation. Never skip step 11 |

---

## Files

| Path | What it is |
|---|---|
| `jobs/billing.py` | The PySpark job: `generate`, `baseline`, `broadcast`, `salted`, `aqe` |
| `stages.py` | Stage table from an event log, plus `--largest`, `--app-time` and `--final-plan` |
| `lib.sh` | The shell helpers `env.sh` sources |
| `live-setup.sh` | Bucket, `generate` batch, BigQuery load. Applies; never destroys |
| `capture.sh` | The recorder. Runs every step and deletes everything through an exit trap |
| `capture/` | Real output, one file per command. Files 16 to 18 are computed from the rehearsal's event logs |
| `plan/` | The four physical plans the job wrote. `skewed-plan.txt` is the plan Lab 10 supplies |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
