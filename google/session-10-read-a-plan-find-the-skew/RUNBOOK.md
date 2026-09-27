# Session 10 walkthrough · Read a plan, find the skew

This walkthrough runs one skewed billing join on Serverless for Apache Spark, reads its plan and its
stage table, fixes it three ways, and runs the same join in BigQuery, in eleven steps. The run used
Serverless for Apache Spark runtime 2.2, which ran Spark 3.5.3 on Java 17, in `us-central1`. Every
command below was run end to end on 27 September 2026. `capture/` holds the full output of each one,
and `plan/` holds the four physical plans the job wrote. You can read the walkthrough and the
captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost about 20 cents at list price. Serverless for Apache Spark
> bills Data Compute Units (DCU) per second with a one-minute minimum, at $0.060 per DCU-hour on the
> standard tier. Each batch runs a driver and two executors of four vCPU and about 13 GB each, which
> is roughly 11 DCU for about three minutes, or under 4 cents a batch across five batches. Shuffle
> storage and the quarter-gigabyte in Cloud Storage cost fractions of a cent. BigQuery loads are
> free, and the queries process about 1 GB in total. Delete what you create, as step 11 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional analytics company in South End, Charlotte, and the same
firm appears in the Session 7 and Session 8 demonstrations. It bills its fleet customers every month
by joining a year of trips, **30,000,000 rows**, to its accounts dimension, **5,001 rows**, and
summing fares by account tier and month.

Street hails carry the account `WALKUP`, which is never invoiced and holds **60 per cent** of the
trips. It is a real value, not a null, so the join's `isnotnull` filter keeps it, and every `WALKUP`
trip hashes to the same partition. That one key is the skew. The job generates its own data from
fixed seeds, so every number below reproduces.

`jobs/billing.py` runs in five modes. `generate` writes the data. `baseline`, `broadcast`, `salted`
and `aqe` run the same join four ways, and each writes its physical plan to `plans/<mode>/` and its
result to `out/<mode>/`. The job uses only built-in DataFrame functions, so no Python function is
serialized to the executors.

---

## Before you start

You need the gcloud CLI with `bq`, Python 3, and Jupyter with a Bash kernel. Nothing in the
demonstration starts Spark on your own machine.

**CPU quota.** Each Spark batch holds 12 vCPUs, one driver and two executors of four vCPUs each.
Serverless batches count against your project's `CPUS_ALL_REGIONS` quota, together with anything
else running in the project, such as Compute Engine VMs or Vertex AI training jobs. Check that quota
on the **Quotas** page of the Console before you start. If fewer than 12 vCPUs are free, stop other
workloads or request a quota increase. The `submit` helper waits for the previous batch to finish
before it starts the next, so the demonstration never needs more than 12 vCPUs at once.

```sh
./live-setup.sh YOUR_PROJECT_ID   # or run prep.ipynb
source ~/dsba6190-live-demo-10/env.sh
gcloud storage du -s "$BASE/data/trips"   # 242,555,519 bytes
```

The script enables the Dataproc API, turns on Private Google Access on the `default` subnet in
`us-central1`, creates the bucket, uploads `billing.py`, runs the `generate` batch, and loads
`trips` and `accounts` into a new BigQuery dataset for steps 4 and 8. It runs none of the four
variants. The `generate` batch took **152 seconds** on the recorded run, so allow about five minutes
for the script.

`env.sh` exports every name the notebook uses and sources `lib.sh`, which defines the helpers.
`submit` sends a batch with `--async`, and `waitfor` polls it until it ends. `planof` prints the
plan a variant wrote, `evlog` prints its stage table, and `biggest` prints the largest task in each
stage that reads a shuffle. `finalplan` prints the plan adaptive execution actually ran, and
`apptime` prints how long the Spark application ran. `bqq` runs a BigQuery query with the cache off
and prints slot time and bytes processed. Every batch carries the properties `capture.sh` used:
runtime 2.2, `spark.eventLog.compress=false`, dynamic allocation off, two executors of four cores,
and 200 shuffle partitions.

Each Spark variant took 164 to 213 seconds from submission to finish. The notebook therefore submits
each batch with `--async` one step before its results are needed and collects it later with
`waitfor`, which polls every ten seconds.

| Batch | Submitted at | Collected at |
|---|---|---|
| `baseline` | step 1 | step 2 |
| `broadcast` | step 2 | step 5 |
| `salted` | step 3 | step 6 |
| `aqe` | step 4 | step 7 |

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. The stage tables are wide, so widen the notebook window.

---

## The sequence

| # | Step |
|---|---|
| 1 | The billing job, and the first batch submitted |
| 2 | Read the plan |
| 3 | The stage table, and the straggler |
| 4 | The cause, in the data |
| 5 | Broadcast: the join shuffle is gone |
| 6 | Salted: one key becomes thirty-two |
| 7 | Adaptive execution: coalesced, not split |
| 8 | The same join in BigQuery |
| 9 | Four variants, one answer |
| 10 | Save and number the plan |
| 11 | Teardown |

### Step 1 · The billing job, and the first batch submitted

```sh
submit baseline baseline "$OFF"
```

Submit the batch first, then read while it runs. `$OFF` switches off adaptive execution and
automatic broadcast so that the baseline shows the raw plan. The data sizes are **242,555,519
bytes** of trips against **27,972 bytes** of accounts. Read the join in `billing.py` and classify
each transformation. The read and the select are narrow, and the join and the `groupBy` are wide.
**What to notice.** Nothing in the code or the sizes shows the skew.

### Step 2 · Read the plan

```sh
waitfor baseline
planof baseline | head -17
submit broadcast broadcast "$OFF"
```

The baseline took **213 seconds** and returned 48 rows. Read the tree from the bottom up. Two `Scan
parquet` leaves each feed a `Filter isnotnull`. `Exchange (4)` and `Exchange (9)` repartition both
sides by `hashpartitioning(account_id, 200)`. A `SortMergeJoin` follows, and `Exchange (14)` serves
the aggregate. **What to notice.** The plan names the key and the partition count. It cannot show
how rows spread across keys.

### Step 3 · The stage table, and the straggler

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
recomputing the join because nothing was cached. It reads less because the `fare` column is pruned.
**What to notice.** The ratio of the slowest task to the median task is the number that reveals
skew.

### Step 4 · The cause, in the data

```sh
submit aqe aqe "$AQE_ON"
bqq "SELECT account_id, COUNT(*) AS trips, ... GROUP BY 1 ORDER BY 2 DESC LIMIT 5"
```

`WALKUP` holds **17,997,932 trips, a share of 0.5999**. The next largest account holds 2,597. **What
to notice.** The cause matches the symptom. The 18,058,073 records in the largest task are the
`WALKUP` trips plus the few ordinary accounts that hash to the same partition.

### Step 5 · Broadcast: the join shuffle is gone

```sh
waitfor broadcast
planof broadcast | sed -n '2,10p'
evlog broadcast
```

`BroadcastExchange (7)` and `BroadcastHashJoin Inner BuildRight (8)` replace the two join Exchanges.
Only `Exchange (11)`, after the join, remains. The only 200-task stage left reads 0.0 MB, and its
slowest task took 2.8 s. The batch took **164 seconds** against the baseline's 213. **What to
notice.** Broadcast needs one side small enough to copy to every executor. Here that side is 5,001
rows.

### Step 6 · Salted: one key becomes thirty-two

```sh
waitfor salted
planof salted | grep -A2 -E '^\((3|5|10)\) (Project|Exchange|Generate)'
evlog salted
biggest salted
```

The plan adds `cast((rand(3) * 32.0) as int) AS salt`, an `explode` on the accounts side, and
`hashpartitioning(account_id, salt, 200)`. The join stage's slowest task falls to **3.1 s** and its
ratio to **8.8**. The largest task reads **7.8 MB**. The shuffle grows to **420.3 MB** because the
accounts are copied 32 times. The batch took **165 seconds**. **What to notice.** Salting works when
neither side is small, and it adds code that someone must maintain.

### Step 7 · Adaptive execution: coalesced, not split

```sh
waitfor aqe
planof aqe | grep -E '^AdaptiveSparkPlan|isFinalPlan'
finalplan aqe | grep -E 'AQEShuffleRead|SortMergeJoin'
evlog aqe
biggest aqe
```

The printed plan says `isFinalPlan=false`. The final plan from the event log shows `AQEShuffleRead
coalesced` on every shuffle and no skew split. The join ran as **5 tasks** with a median of 9.0 s
and a maximum of **20.0 s**, a ratio of **2.2**. The largest task still read **206.2 MB**, which is
below the default `skewedPartitionThresholdInBytes` of 256 MB, so adaptive execution never treated
it as skewed. The batch took **169 seconds**. **What to notice.** The ratio improved because the
median rose, and the straggler got longer. Adaptive execution does not replace knowledge of the
data.

### Step 8 · The same join in BigQuery

```sh
bqq "SELECT a.tier, DATE_TRUNC(t.pickup_date, MONTH) AS month, COUNT(*) AS trips, ... JOIN ..."
```

BigQuery used **1.4 slot-seconds, processed 686.7 MB, and ran 4 stages**, with no batch to start.
**What to notice.** When the work fits in SQL, the SQL version is shorter and starts at once. Weigh
which version the billing team would rather maintain.

### Step 9 · Four variants, one answer

Every variant returns **48 rows and 1.14017810626E9** in revenue, which is $1,140,178,106.26.
`apptime` shows that the Spark applications ran **111.9, 72.7, 78.9 and 80.7 seconds** inside
batches of 213, 164, 165 and 169 seconds. **What to notice.** Between 86 and 101 seconds of every
batch went to provisioning and shutdown. That is the measured startup cost of serverless Spark.

### Step 10 · Save and number the plan

```sh
planof baseline > skewed-plan.txt
nl -ba -w2 -s '  ' skewed-plan.txt | sed -n '6,16p'
```

The command saves the baseline plan and prints lines 6 to 16 with line numbers, from the join down
to the two scans. The same plan is in `plan/skewed-plan.txt`. **What to notice.** Line numbers let
you refer to each operator in the plan exactly.

### Step 11 · Teardown

```sh
gcloud storage rm -r "gs://${BUCKET:?}"
bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"
gcloud dataproc batches list --region "$REGION" --filter="state=RUNNING"
```

A finished batch releases its own machines. The bucket and the dataset hold the data, the plans, the
event logs and four result tables. The recorded run listed **0** running batches afterwards. Every
name is written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong
thing.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| A batch fails within seconds with `Insufficient 'CPUS_ALL_REGIONS' quota` | Another batch or another workload holds your project's vCPUs. Run `waitfor` on the previous batch, stop other workloads, and submit again. If your quota is below 12 vCPUs, request an increase |
| `submit` prints that it is waiting for a batch to finish | The previous batch is still running. `submit` starts the next one when the vCPUs are free |
| `waitfor` is still polling when you reach its step | The batch is still running. Continue with the next step and collect the batch afterwards |
| A batch ends `FAILED` | Read the last lines `waitfor` prints, then resubmit with `submit <name> <mode> "$OFF"` |
| A batch fails within a minute with a network error | The subnet has no Private Google Access, and a serverless batch has no external IP. `live-setup.sh` checks the `default` subnet and enables it |
| `stages.py` fails with a `UnicodeDecodeError` or a JSON error | The event log is compressed. Keep `spark.eventLog.compress=false` in `COMMON` in `lib.sh` |
| A helper fails to open a file whose path is cut at a space | The repository sits in a path with spaces. `live-setup.sh` copies `stages.py` and `lib.sh` to `~/dsba6190-live-demo-10`, and `env.sh` changes into it |
| `evlog` prints `no finished event log ... yet` | The batch is still running, so its log is still `.inprogress`. Run `waitfor` for that variant first |
| A local `pyspark` shell fails with pickling errors | Your local Python is newer than the local PySpark supports. The demonstration never starts Spark locally, and the job uses no Python function that needs pickling |

---

## Files

| Path | What it is |
|---|---|
| `jobs/billing.py` | The PySpark job: `generate`, `baseline`, `broadcast`, `salted`, `aqe` |
| `stages.py` | The stage table from an event log, plus `--largest`, `--app-time` and `--final-plan` |
| `lib.sh` | The shell helpers that `env.sh` sources |
| `live-setup.sh` | The bucket, the `generate` batch and the BigQuery load. It creates resources and never deletes them |
| `capture.sh` | The recorder. It runs every step and deletes everything through an exit trap |
| `capture/` | Real output, one file per command. Files 16 to 18 are computed from the recorded run's event logs |
| `plan/` | The four physical plans the job wrote |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
