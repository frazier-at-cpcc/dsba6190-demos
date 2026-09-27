# Session 14 walkthrough · Green status, wrong data

This walkthrough follows one nightly BigQuery load through eight steps on BigQuery, Cloud Storage,
Cloud Logging and Cloud Monitoring, with BigQuery CLI 2.1.38 and Google Cloud CLI 586.0.0. Every
command below was run end to end on 27 September 2026, and `capture/` holds the full output of each
one. You can read the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under one cent. Load jobs are free, the table is about
> 70 MB, and every query sits inside the monthly free tebibyte. A log-based metric and an alerting
> policy at this volume are free. Delete what you create, in the order step 8 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Crown Street Markets

**Crown Street Markets** is a fictional 40-store Charlotte grocery chain. Its stores sit in four
regions: Center City, South, North and East. Every night a job loads the previous day's register
baskets into BigQuery, about 12,300 of them. The replenishment dashboard reads the table at 06:00 to
decide what each store reorders. If last night's data is wrong, tomorrow's shelves are wrong.

The table, `store_sales`, holds one row per basket. It is partitioned by `sale_date` and carries the
labels `team:replenishment`, `pipeline:nightly-store-sales` and `env:demo`. Staging loads 59 nights,
726,438 rows, and leaves last night for step 1. Three more files for last night wait in the bucket's
`incoming/` folder, and each one loads without an error. Step 3 loads them one at a time and lets
the checks show what is wrong with each.

`sample/make-store-sales.py` generates every file from a fixed seed. "Last night" is always
yesterday on the machine that stages it. The freshness check therefore holds on the day you stage,
and every other figure below reproduces.

---

## Before you start

```sh
./live-setup.sh YOUR_PROJECT_ID        # or run prep.ipynb
source ~/dsba6190-live-demo-14/env.sh
```

The script generates sixty nights of files, creates a labelled bucket and uploads them, creates the
partitioned table, and backfills fifty-nine nights in one load job. It also loads `load_runs`,
thirty nights of load outcomes for step 5. Staging takes about two minutes. Run the steps on the
same day you stage, because the freshness check expects last night to be yesterday. `env.sh` loads
the helpers from `lib.sh`:

| Helper | What it does |
|---|---|
| `q "<sql>"` | Runs a query with the cache off, then prints MB processed and billed. `PIPELINE=<name> q` sets the job's label |
| `nightly_load <gs://uri>` | Replaces last night's partition with one file, exactly as the nightly job does, and prints the job's state, errors and rows |
| `checks` | Runs the four checks in `sql/checks.sql` |
| `log_checks` | Runs them again and writes each result to Cloud Logging as one structured JSON entry |
| `red_count` | Reads the log-based metric's recent points back from Cloud Monitoring |

`nightly_load` uses `--autodetect`, `--source_column_match=NAME` and
`--schema_update_option=ALLOW_FIELD_ADDITION`. That combination is a common and reasonable loader.
It is also the reason a renamed column arrives as a new nullable column instead of an error.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Before step 4, replace `instructor@example.edu` in the channel cell with your
own email address.

---

## The sequence

| # | Step |
|---|---|
| 1 | The nightly load succeeds |
| 2 | Four checks in SQL |
| 3 | Break it three ways, and every load succeeds |
| 4 | Make one check a symptom alert |
| 5 | The SLO and the error budget |
| 6 | Delete by mistake, restore with time travel |
| 7 | FinOps: labels, the cheapest fix, a storage move |
| 8 | Teardown, verified |

### Step 1 · The nightly load succeeds

```
$ nightly_load gs://$BUCKET/raw/dt=$LAST_NIGHT/sales.csv
load job   s14_load_1790539198_13126
state      DONE
errors     none
rows       12270
into       store_sales$20260926
```

The first cell shows the table's labels and partitioning. The second runs the load. **What to
notice.** The output is everything most pipelines report: a job, a state, no errors and a row count.
Consider what else you would need to see before you trusted the dashboard at 06:00.

### Step 2 · Four checks in SQL

```
| signal       | observed                       | expected                  | status |
| freshness    | newest 2026-09-26, 0 h old     | yesterday, < 26 h         | GREEN  |
| volume       | 12270 rows, 100% of 7-day mean | 80 to 120%                | GREEN  |
| schema       | matches contract               | 9 columns, typed          | GREEN  |
| distribution | null 0.0%, mean $45.46         | null < 1.0%, $45.75 ± 10% | GREEN  |
processed 21.5 MB · billed 30.0 MB · label pipeline:dq_checks
```

Open `sql/checks.sql` beside the output. Freshness reads `INFORMATION_SCHEMA.PARTITIONS`. Volume
compares last night with the trailing seven nights. Schema compares `INFORMATION_SCHEMA.COLUMNS`
with a nine-column contract. Distribution compares the null rate and the mean basket with the
trailing values. **What to notice.** Each check is one ordinary query. The bill is 30 MB because the
query touches three tables, and each carries BigQuery's 10 MB minimum. Step 7 returns to that
figure.

### Step 3 · Break it three ways, and every load succeeds

```
nightly_load one-store.csv        state DONE  errors none  rows 377
  volume        377 rows, 3% of 7-day mean        RED
nightly_load renamed-column.csv   state DONE  errors none  rows 12270
  schema        extra basket_total                RED
  distribution  null 100.0%, mean $0.00           RED
nightly_load north-nulls.csv      state DONE  errors none  rows 12270
  distribution  null 19.2%, mean $45.50           RED
```

Run each load, confirm that it reports `DONE`, then run `checks`. Between the second and third
breaks, reload the good file and drop the added column with `ALTER TABLE ... DROP COLUMN
basket_total`. After the third, the region query shows that all 2,352 North rows have an empty
`basket_value`. Reload the good file, and all four checks return to green.

**What to notice.** Three wrong nights produced three green jobs. The renamed column did not fail
the load. The loader added `basket_total` as a new nullable column and left `basket_value` empty. In
the North break the mean basket stayed at $45.50 against a trailing $45.75, because `AVG` ignores
nulls. The null rate caught the break, and the mean never would have. The one-store load wrote 377
rows, one store's worth, which is what a failed upstream feed looks like.

### Step 4 · Make one check a symptom alert

```sh
log_checks                                                   # gcloud logging write, one JSON entry per check
gcloud logging metrics create "$METRIC" --config-from-file=metric.yaml
CHANNEL=$(gcloud beta monitoring channels create --type=email \
            --channel-labels=email_address=instructor@example.edu ...)
POLICY=$(gcloud monitoring policies create --policy-from-file=policy.json \
            --notification-channels="$CHANNEL" ...)
```

`metric.yaml` counts entries whose `jsonPayload.status` is `RED` and extracts the check's name as a
label. `policy.json` fires when that count exceeds zero in a five-minute window. It carries
documentation that tells the person paged what to do. The next cells break last night once more and
run `log_checks`. The volume entry is written at severity `ERROR`. `gcloud logging read` returns it
as structured fields, and `red_count` reads the metric's point back from Cloud Monitoring.

A new log-based metric can take several minutes to become visible to Cloud Monitoring. The policy
cell retries every 30 seconds until it does. The recorded run needed one retry, about 30 seconds.

**What to notice.** The alert watches the symptom a user feels, a wrong dashboard. It does not watch
a cause such as a failed job, which never happened. Use your own email address for the channel. In
production, a channel points at an on-call rotation, never at one person's inbox.

### Step 5 · The SLO and the error budget

```
| sli                     | bad_min | budget_min | sli_pct | budget_used_pct |
| job DONE by 06:00       |     297 |      432.0 |   99.31 |            68.8 |
| data fresh and complete |     737 |      432.0 |   98.29 |           170.6 |
```

`load_runs` holds thirty nights. Two loads finished late, 102 and 195 minutes after 06:00. A third
finished on time with 355 rows, a partial feed, and was not corrected until 13:20. The SLO is 99 per
cent of the month's 43,200 minutes, so the budget is 432 minutes.

**What to notice.** Measured on job status, the load met its SLO with 69 per cent of the budget
spent. Measured on the data, the same month spent 171 per cent, and the team should have frozen
risky changes a week earlier. The choice of SLI decides which of those two months the team believes
it had.

### Step 6 · Delete by mistake, restore with time travel

```sql
DELETE FROM store_sales
WHERE sale_date = '$LAST_NIGHT'
-- AND register_id = 'CLT-040-R99'   the line that was meant to be here

CREATE TEMP TABLE lost AS
  SELECT * FROM store_sales FOR SYSTEM_TIME AS OF TIMESTAMP '$BEFORE'
  WHERE sale_date = '$LAST_NIGHT';
INSERT INTO store_sales SELECT * FROM lost;
```

An analyst clearing a test register's baskets runs the statement without its second line and deletes
all 12,270 of last night's rows. `checks` then turns freshness red, because the newest partition is
now the night before, and volume reads zero. The restore runs, `checks` returns to green, and a
query reads the event back from `INFORMATION_SCHEMA.JOBS`. In the recorded run the delete finished
at 20:04:01 UTC and the restore at 20:04:10, nine seconds later. The run deleted 12,270 rows and
inserted 12,270. The last cell creates a snapshot of the table in a separate dataset.

**What to notice.** The recovery point is the timestamp taken before the delete, so the RPO for this
event is zero rows. The RTO is seconds only because the mistake was noticed at once. In production,
the RTO runs from the mistake to the moment someone notices. The restore needs a temporary table
because BigQuery refuses to read and write one table at two different snapshot times in one
statement. Time travel reaches back seven days. The snapshot lives in another dataset so that it
survives the loss of the first one.

### Step 7 · FinOps: labels, the cheapest fix, a storage move

```
dashboard, as written   WHERE DATE_DIFF(CURRENT_DATE(), sale_date, DAY) BETWEEN 1 AND 7
                        processed 24.0 MB · billed 25.0 MB
dashboard, pruned       WHERE sale_date BETWEEN DATE_SUB(..., 7) AND DATE_SUB(..., 1)
                        processed 2.8 MB · billed 10.0 MB
```

Both queries return 280 store-days and $3,931,870. The first wraps the partition column in a
function, so BigQuery cannot prune and reads all sixty nights. The second compares the column with
constants and reads seven. The next cell groups `INFORMATION_SCHEMA.JOBS` by the `pipeline` label,
which every job in the demonstration carries. The last cells apply the lifecycle rule and move the
oldest raw file to Nearline.

**What to notice.** The data-quality checks billed 270 MB across nine runs, nearly eight times the
dashboard's 35 MB, because each run pays the 10 MB minimum three times. Labels make that cost
visible. The storage move changes the object's class and generation and leaves its `gs://` URL
alone, so the load job and every other consumer keep working.

### Step 8 · Teardown, verified

```sh
gcloud monitoring policies delete "${POLICY:?}"      # first: a metric in use cannot be deleted
gcloud beta monitoring channels delete "${CHANNEL:?}"
gcloud logging metrics delete "${METRIC:?}"; gcloud logging logs delete "${LOG:?}"
gcloud storage rm -r "gs://${BUCKET:?}"
bq rm -r -f -d "${DATASET:?}"; bq rm -r -f -d "${BACKUP:?}"
```

The last cell counts every resource type whose name carries the run's suffix, and every count is
zero. Every name is written `${NAME:?}`, so an empty variable refuses to run instead of deleting the
wrong thing. **What to notice.** Order matters. Cloud Logging refuses to delete a metric that an
alerting policy still uses, so the policy goes first.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| The policy cell prints "not visible to Monitoring yet" | A new metric takes time to appear. The cell retries every 30 seconds. Wait for it |
| `red_count` prints nothing | The metric samples once a minute. Continue to step 5 and rerun `red_count` afterwards |
| `gcloud logging read` returns nulls | The entry is not indexed yet. Wait ten seconds and rerun the cell |
| Freshness is red in step 2 | The table was staged on an earlier day, so last night is no longer yesterday. Restage with `prep.ipynb` |
| The restore reports an invalid time-travel timestamp | `$BEFORE` was lost with the kernel. Set it to a UTC time a few seconds before the delete and rerun |
| A query that opens with a `--` comment fails as an unknown flag | Pass the query through `q`, which adds a leading space |
| `gcloud storage cat` piped to `head` fails its hash check | Read the file with `sed -n 1,3p`, which consumes the whole object |
| Credentials expire | Run `gcloud auth login` and rerun the cell |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-store-sales.py` | The seeded generator: sixty good nights, three incoming files, thirty load outcomes |
| `sql/checks.sql`, `sql/error-budget.sql` | The four checks and the error-budget arithmetic |
| `monitoring/` | The log-based metric, the alerting policy and the lifecycle rule, with placeholders that `live-setup.sh` fills |
| `lib.sh` | `q`, `nightly_load`, `checks`, `log_checks` and `red_count` |
| `live-setup.sh` | Generates, uploads and backfills. It creates resources and never deletes them |
| `capture.sh` | The recorder. It runs all eight steps and removes everything through an exit trap |
| `capture/` | The real output, one file per command |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
