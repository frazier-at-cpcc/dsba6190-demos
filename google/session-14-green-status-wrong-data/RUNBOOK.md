# Session 14 live demo · runbook

Green status, wrong data. Forty minutes, eight steps, 1:00 to 1:40.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: BigQuery, Cloud
Storage, Cloud Logging and Cloud Monitoring, BigQuery CLI 2.1.38 and Google Cloud CLI 586.0.0. Every
command below was run, and `capture/` holds the full output of each one.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you reproduce it on your own account it
> costs under one cent: load jobs are free, the table is about 70 MB, every query sits inside the
> monthly free tebibyte, and a log-based metric and an alerting policy at this volume are free.
> Opening an account requires a credit card at signup, though Google does not charge it. **Destroy
> what you create.** Step 8 does, and verifies it.

---

## The scenario · Crown Street Markets store sales

**Crown Street Markets** is fictional: the 40-store Charlotte grocery chain from Sessions 2, 6, 11
and 12. Its stores sit in four regions, Center City, South, North and East. Every night a job loads
the previous day's register baskets into BigQuery, about 12,300 of them, and the replenishment
dashboard reads the table at 06:00 to decide what each store reorders. If last night's data is
wrong, tomorrow's shelves are wrong.

The table, `store_sales`, holds one row per basket, is partitioned by `sale_date` and carries the
labels `team:replenishment`, `pipeline:nightly-store-sales` and `env:demo`. Staging loads 59 nights,
726,438 rows. Last night waits for step 1. `sample/make-store-sales.py` generates every file from a
fixed seed, and "last night" is always yesterday on the machine that stages it, so the freshness
check holds on the day of class and every other figure below reproduces.

**Three incoming files each carry one defect, and each loads without an error.**

| File | Defect | What catches it |
|---|---|---|
| `one-store.csv` | Only the Uptown store's feed arrived: 377 rows, 3 per cent of a night | Volume |
| `renamed-column.csv` | The upstream extract renamed `basket_value` to `basket_total` | Schema and distribution |
| `north-nulls.csv` | `basket_value` is empty for every North store, 19.2 per cent of rows | Distribution |

---

## How the demonstration fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:50 | Concept Block 1 · Keeping it alive and affordable | 40 |
| 0:50–1:00 | Break | 10 |
| **1:00–1:40** | **This demonstration** | **40** |
| 1:40–2:20 | Production-readiness review, Piedmont Crescent Grocers | 40 |
| 2:20–2:55 | Lab 14 start | 35 |
| 2:55–3:00 | Wrap and final-examination orientation | 5 |

The demonstration performs four Hour 1 segments, so Concept Block 1 is ten minutes shorter. The lab
gives up thirty. The review keeps its forty minutes and follows directly, while the controls
Piedmont Crescent lacks are still on the screen.

---

## Before class

```sh
cd "lectures/demos/session-14-green-status-wrong-data"
./live-setup.sh YOUR_PROJECT_ID        # or run prep.ipynb
source ~/dsba6190-live-demo-14/env.sh
```

It generates sixty nights of files, creates a labelled bucket and uploads them, creates the
partitioned table, and backfills fifty-nine nights in one load job. It also loads `load_runs`,
thirty nights of load outcomes for step 5. It takes about two minutes. `env.sh` loads four helpers
from `lib.sh`:

| Helper | What it does |
|---|---|
| `q "<sql>"` | Runs a query with the cache off, then prints MB processed and billed. `PIPELINE=<name> q` sets the job's label |
| `nightly_load <gs://uri>` | Replaces last night's partition with one file, exactly as the nightly job does, and prints the job's state, errors and rows |
| `checks` | Runs the four checks in `sql/checks.sql` |
| `log_checks` | Runs them again and writes each result to Cloud Logging as one structured JSON entry |

`nightly_load` uses `--autodetect`, `--source_column_match=NAME` and
`--schema_update_option=ALLOW_FIELD_ADDITION`. That is a common and reasonable loader, and it is the
reason a renamed column arrives as a new nullable column instead of an error.

**Drive the demonstration from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**,
**Jupyter Kernel**, **Bash**.

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | The nightly load succeeds | 4 | 26 |
| 2 | Four checks in SQL | 5 | 27 |
| 3 | Break it three ways; every load succeeds | 8 | 28 |
| 4 | Make one check a symptom alert | 6 | 29 |
| 5 | The SLO and the error budget | 4 | 30 |
| 6 | Delete by mistake, restore with time travel | 6 | 31 |
| 7 | FinOps: labels, the cheapest fix, a storage move | 5 | 32 |
| 8 | Teardown, verified | 2 | 33 |

Slide 22 is the divider, slide 23 introduces the scenario, and slides 24 and 25 carry the run sheet.
The review begins at slide 34. The deck runs to 52 slides.

### Step 1 · The nightly load succeeds · slide 26 · 4 minutes

```
$ nightly_load gs://$BUCKET/raw/dt=$LAST_NIGHT/sales.csv
load job   s14_load_1790539198_13126
state      DONE
errors     none
rows       12270
into       store_sales$20260926
```

Show the table's labels and partitioning first, then run the load. **What to notice.** This is
everything most pipelines report: a job, a state, no errors, a row count. Ask the room what they
would need to see before trusting the dashboard at 06:00.

### Step 2 · Four checks in SQL · slide 27 · 5 minutes

```
| signal       | observed                       | expected                  | status |
| freshness    | newest 2026-09-26, 0 h old     | yesterday, < 26 h         | GREEN  |
| volume       | 12270 rows, 100% of 7-day mean | 80 to 120%                | GREEN  |
| schema       | matches contract               | 9 columns, typed          | GREEN  |
| distribution | null 0.0%, mean $45.46         | null < 1.0%, $45.75 ± 10% | GREEN  |
processed 21.5 MB · billed 30.0 MB · label pipeline:dq_checks
```

Open `sql/checks.sql` beside the output. Freshness reads `INFORMATION_SCHEMA.PARTITIONS`, volume
compares last night with the trailing seven nights, schema compares `INFORMATION_SCHEMA.COLUMNS`
with a nine-column contract, and distribution compares the null rate and mean basket with the
trailing values. **What to notice.** Each check is one ordinary query. The bill is 30 MB because the
query touches three tables, and each carries BigQuery's 10 MB minimum. Step 7 returns to that.

### Step 3 · Break it three ways · slide 28 · 8 minutes

```
nightly_load one-store.csv        state DONE  errors none  rows 377
  volume        377 rows, 3% of 7-day mean        RED
nightly_load renamed-column.csv   state DONE  errors none  rows 12270
  schema        extra basket_total                RED
  distribution  null 100.0%, mean $0.00           RED
nightly_load north-nulls.csv      state DONE  errors none  rows 12270
  distribution  null 19.2%, mean $45.50           RED
```

Run each load, read its `DONE` aloud, then run `checks`. Between the second and third breaks, reload
the good file and drop the added column with `ALTER TABLE ... DROP COLUMN basket_total`. After the
third, reload the good file and show all four green again.

**What to notice.** Three wrong nights, three green jobs. The renamed column did not fail the load:
the loader added `basket_total` as a new nullable column and left `basket_value` empty. In the North
break the mean basket stayed at $45.50 against a trailing $45.75, because `AVG` ignores nulls. The
null rate caught it and the mean never would have. Point at the one-store row count: 377 rows is a
store's worth, which is what a failed upstream feed looks like.

### Step 4 · Make one check a symptom alert · slide 29 · 6 minutes

```sh
log_checks                                                   # gcloud logging write, one JSON entry per check
gcloud logging metrics create "$METRIC" --config-from-file=metric.yaml
CHANNEL=$(gcloud beta monitoring channels create --type=email \
            --channel-labels=email_address=instructor@example.edu ...)
POLICY=$(gcloud monitoring policies create --policy-from-file=policy.json \
            --notification-channels="$CHANNEL" ...)
```

`metric.yaml` counts entries whose `jsonPayload.status` is `RED` and extracts the check's name as a
label. `policy.json` fires when that count exceeds zero in a five-minute window and carries
documentation that tells the person paged what to do. Then break last night once more and run
`log_checks`: the volume entry is written at severity `ERROR`, `gcloud logging read` returns it as
structured fields, and `red_count` reads the metric's point back from Cloud Monitoring.

**What to notice.** The alert watches the symptom a user feels, a wrong dashboard, and not a cause
such as a failed job, which never happened. The channel is `instructor@example.edu`, a reserved domain
that delivers nowhere. A real channel points at a rotation, never at one person's inbox.

**A new log-based metric can take several minutes to become visible to Monitoring.** The policy cell
retries every 30 seconds until it does. Keep talking through the policy file while it retries. The
rehearsal needed one retry, about 30 seconds, and an earlier rehearsal failed outright without the retry.

### Step 5 · The SLO and the error budget · slide 30 · 4 minutes

```
| sli                     | bad_min | budget_min | sli_pct | budget_used_pct |
| job DONE by 06:00       |     297 |      432.0 |   99.31 |            68.8 |
| data fresh and complete |     737 |      432.0 |   98.29 |           170.6 |
```

`load_runs` holds thirty nights. Two finished late, 102 and 195 minutes after 06:00. A third
finished on time with 355 rows, a partial feed, and was not corrected until 13:20. The SLO is 99 per
cent of the month's 43,200 minutes, so the budget is 432 minutes.

**What to notice.** Measured on job status, the load met its SLO with 69 per cent of the budget
spent. Measured on the data, the same month spent 171 per cent, and the team should have frozen
risky changes a week ago. The SLI decides which of those two months the team believes it had.

### Step 6 · Delete by mistake, restore with time travel · slide 31 · 6 minutes

```sql
DELETE FROM store_sales
WHERE sale_date = '$LAST_NIGHT'
-- AND register_id = 'CLT-040-R99'   the line that was meant to be here

CREATE TEMP TABLE lost AS
  SELECT * FROM store_sales FOR SYSTEM_TIME AS OF TIMESTAMP '$BEFORE'
  WHERE sale_date = '$LAST_NIGHT';
INSERT INTO store_sales SELECT * FROM lost;
```

An analyst clearing a test register's baskets runs the statement without its second line and
deletes all 12,270 of last night's rows. Run `checks`: freshness goes red because the newest
partition is now the night before, and volume reads zero. Restore, run `checks` again, then read
the event back from `INFORMATION_SCHEMA.JOBS`. On the rehearsal the delete finished at 20:04:01 UTC
and the restore at 20:04:10, nine seconds later, with 12,270 rows deleted and 12,270 inserted. Last,
create a snapshot of the table in a
separate dataset.

**What to notice.** The recovery point is the timestamp taken before the delete, so the RPO for this
event is zero rows. The RTO is seconds only because the mistake was noticed at once; in production
it runs from the mistake to the moment someone notices. The restore needs a temporary table because
BigQuery refuses to read and write one table at two different snapshot times in one statement. Time
travel reaches back seven days. The snapshot lives in another dataset so that it survives the loss of
the first one.

### Step 7 · FinOps · slide 32 · 5 minutes

```
dashboard, as written   WHERE DATE_DIFF(CURRENT_DATE(), sale_date, DAY) BETWEEN 1 AND 7
                        processed 24.0 MB · billed 25.0 MB
dashboard, pruned       WHERE sale_date BETWEEN DATE_SUB(..., 7) AND DATE_SUB(..., 1)
                        processed 2.8 MB · billed 10.0 MB
```

Both return 280 store-days and $3,931,870. The first wraps the partition column in a function, so
BigQuery cannot prune and reads all sixty nights. The second compares the column with constants and
reads seven. Then group `INFORMATION_SCHEMA.JOBS` by the `pipeline` label, which every job in the
demonstration carries. Last, apply the lifecycle rule and move the oldest raw file to Nearline.

**What to notice.** The data-quality checks billed 270 MB across nine runs, nearly eight
times the dashboard's 35 MB, because each run
pays the 10 MB minimum three times. Labels are what make that visible. The storage move changes the
object's class and generation and leaves its `gs://` URL alone, so the load job and every other
consumer keep working. This is the lab's tiering pattern at the scale of one file.

### Step 8 · Teardown, verified · slide 33 · 2 minutes

```sh
gcloud monitoring policies delete "${POLICY:?}"      # first: a metric in use cannot be deleted
gcloud beta monitoring channels delete "${CHANNEL:?}"
gcloud logging metrics delete "${METRIC:?}"; gcloud logging logs delete "${LOG:?}"
gcloud storage rm -r "gs://${BUCKET:?}"
bq rm -r -f -d "${DATASET:?}"; bq rm -r -f -d "${BACKUP:?}"
```

The last cell counts every resource type whose name carries the run's suffix, and every count is
zero. **What to notice.** Order matters: Cloud Logging refuses to delete a metric that a policy still
uses. The `:?` guards refuse to run with an empty name.

---

## If it fails live

| What happened | Do this |
|---|---|
| The policy cell prints "not visible to Monitoring yet" | Expected for a new metric. Keep talking; it retries every 30 seconds |
| `red_count` prints nothing | The metric samples once a minute. Move to step 5 and rerun it afterwards |
| `gcloud logging read` returns nulls | The entry is not indexed yet. Wait ten seconds and rerun |
| Freshness is red in step 2 | The table was staged on an earlier day, so last night is no longer yesterday. Restage with `prep.ipynb` |
| The restore reports an invalid time-travel timestamp | `$BEFORE` was lost with the kernel. Set it to a UTC time a few seconds before the delete and rerun |
| Credentials expire | `gcloud auth login`, or present the capture slides and say the output is recorded |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-store-sales.py` | The seeded generator: sixty good nights, three defective files, thirty load outcomes |
| `sql/checks.sql`, `sql/error-budget.sql` | The four checks and the error-budget arithmetic |
| `monitoring/` | The log-based metric, the alerting policy and the lifecycle rule, with placeholders `live-setup.sh` fills |
| `lib.sh` | `q`, `nightly_load`, `checks`, `log_checks` and `red_count` |
| `live-setup.sh` | Generates, uploads and backfills. Applies; never destroys |
| `capture.sh` | The recorder. Runs all eight steps and removes everything through an exit trap |
| `capture/` | Real output, one file per command |
| `prep.ipynb`, `demo.ipynb` | Bash notebooks, commands only, from `build-notebook.py` |
