# Session 7 walkthrough · Make the cost visible, then govern it

This walkthrough prices BigQuery queries before they run and then governs the same data as a
lakehouse, in twelve steps on BigQuery, Cloud Storage, a BigQuery connection and Data Catalog, all
in the `US` multi-region. Steps 1 to 8 make the cost of a query visible. Steps 9 to 11 control who
can read which columns and rows. Every command below was run end to end on 24 September 2026 with
BigQuery CLI 2.1.38 and Google Cloud SDK 586.0.0, and `capture/` holds the full output of each one.
You can read the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under $0.10 at list price. It scanned about 8.5 GB on
> demand in the steps, most of it the two tables built in step 7, and about 3.5 GB in the Parquet
> export. At $6.25 per TiB that is under eight cents. The first tebibyte of queries each month is
> free, so a project with its monthly allowance intact pays nothing for the queries. Storage for an
> hour is a fraction of a cent. Steps 1 to 6 are dry runs and cost nothing. Delete what you create,
> in the order step 12 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional twelve-person analytics company in South End,
Charlotte. It sells demand and pricing dashboards to ground-transportation fleets. It uses New
York's public trip records as its benchmark market, because they form the largest public trip
dataset available. The company builds and prices its product on that data before it has Charlotte
customers.

| Step | What it is in the scenario |
|---|---|
| 1 to 6 | The cost of the dashboards the company sells, which refresh every five minutes |
| 7 | The airport product. JFK, zone 132, stands in for Charlotte Douglas |
| 8 | The reason the airport query is fast enough to sell |
| 9 | A month of trips kept in the company's raw zone |
| 10 | The analyst at the first fleet customer, who is the second principal. Rider locations are refused |
| 11 | That analyst sees only the customer's trips, and Queen City's own analysts see every trip |
| 12 | Closing the demonstration environment |

In the public data, `vendor_id` records the technology provider that logged a trip. In step 11 it
stands in for the customer's fleet.

---

## Before you start

You need a Google Cloud project with billing linked, the `gcloud`, `bq`, `jq` and `curl`
command-line tools, and an account that can create service accounts and grant roles on the project.
The Owner role covers every command.

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-07/env.sh
```

The script enables five APIs and creates the second principal, `dsba6190-analyst`, if it does not
exist. It creates the dataset and the bucket, and it exports one month of 2022 taxi trips to the
bucket as Parquet. It creates the BigQuery connection and grants the connection's service account
read access to the bucket. It imports a taxonomy with one policy tag and grants your own account
Fine-Grained Reader on that tag. It grants the second principal the dataset and nothing else. It
creates no table. Steps 7, 9, 10 and 11 create every table, the tag attachment and both row
policies.

The script takes 2 to 7 minutes. The slow part is IAM. The first time the second principal was
created, its impersonation grant took about five minutes to propagate, and the script waits until
the principal can run a query. With the principal already in place, the script was ready in two
seconds. The default working directory is `~/dsba6190-live-demo-07`.

Sourcing `env.sh` puts `$PROJECT`, `$DS`, `$BUCKET`, `$CONNECTION`, `$POLICY_TAG`, `$ANALYST`,
`$TAXI` and `$WILD` into the shell, and loads four helpers:

| Helper | What it does |
|---|---|
| `dry "<sql>"` | A dry run. It prints the estimate the editor would show, in GB, and costs nothing |
| `q "<sql>"` | Runs the query with the cache off, then prints bytes processed, bytes billed and slot time |
| `plan` | Prints the stages, rows, shuffle bytes and parallelism of the last `q` |
| `as_analyst <command>` | Runs one command as the second principal, through impersonation |

Verify the staging before step 1:

```sh
as_analyst q "SELECT SESSION_USER() AS who"
bq --project_id="$PROJECT" --location=US \
  show --connection "$CONNECTION" | head -3
gcloud storage ls "gs://$BUCKET/trips/2022-01/"
```

Expect the second principal's address, the connection, and three Parquet files. If the first command
fails with `iam.serviceAccounts.getAccessToken`, the impersonation grant has not propagated. Wait
two minutes and run it again.

| Staged resource | Step | What it is |
|---|---|---|
| `gs://dsba6190-trips-<SUFFIX>/trips/2022-01/` | 9 to 11 | January 2022, 2,463,900 trips, three Parquet files, 59 MB |
| `dsba6190-lake-<SUFFIX>` connection | 10 | Holds `roles/storage.objectViewer` on the bucket |
| taxonomy `dsba6190-<SUFFIX>`, tag `trip_location` | 10 | Fine-grained access control activated, your account granted |
| `dsba6190-analyst` | 10, 11 | Dataset viewer and job user, with no storage access and no tag access |

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Steps 1 to 6 also work in the BigQuery editor, where the validator in the top
right corner shows the same estimate. `sql/bytes-scanned.sql` holds those queries ready to paste.
The full `demo.ipynb` ran in 153 seconds on 27 September 2026, and `prep.ipynb` in 90 seconds.

---

## The sequence

The captured outputs below carry the recorded run's suffix, `72583`.

| # | Step |
|---|---|
| 1 | The estimator prices a query before it runs |
| 2 | `SELECT *`, and the number to beat |
| 3 | Three named columns |
| 4 | `LIMIT 10` changes nothing |
| 5 | `COUNT(*)` reads no bytes |
| 6 | Two filters, identical rows |
| 7 | Partition and cluster, built live |
| 8 | The execution plan is the Dremel model |
| 9 | An external table, and an estimate of zero |
| 10 | BigLake, delegation, and a policy tag |
| 11 | Row access policies, two principals, one query |
| 12 | Teardown |

### Step 1 · The estimator prices a query before it runs

In the BigQuery editor, paste query 3 from `sql/bytes-scanned.sql` and do not press Run. The
validator reads "This query will process 1.07 GB when run." The terminal form gives the same figure:

```sh
bq --project_id="$PROJECT" --location=US --quiet query \
  --use_legacy_sql=false --dry_run \
  "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$TAXI\`"
bq --project_id="$PROJECT" show --format=json "${TAXI/./:}" \
  | jq '{numRows, numBytes}'
```

```
Query successfully validated. Assuming the tables are not modified,
running this query will process 1150274528 bytes of data.

{ "numRows": "36256539", "numBytes": "7487651196" }
```

**What to notice.** BigQuery states the price before you pay it, and the estimate is free. No other
engine in this course does that. Pricing a query before running it is the habit the rest of the cost
steps build on.

### Step 2 · `SELECT *`, and the number to beat

```sh
dry "SELECT * FROM \`$TAXI\`"
```

```
This query will process 6.97 GB when run.   (7487651196 bytes)
```

**What to notice.** Every later query in this half is measured against **6.97 GB**. At $6.25 per TiB
this query costs about four cents. A dashboard tile on a five-minute refresh runs it 8,640 times a
month, which is about $370 for one tile.

### Step 3 · Three named columns

```sh
dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$TAXI\`"
dry "SELECT AVG(fare_amount) FROM \`$TAXI\`"
```

```
This query will process 1.07 GB when run.   (1150274528 bytes)
This query will process 0.54 GB when run.   (580104624 bytes)
```

**What to notice.** Naming three columns costs 6.5 times less, for a one-line edit. The second query
halves the cost again because it reads one column. The average itself costs nothing to compute.
Columnar storage bills per column touched.

### Step 4 · `LIMIT 10` changes nothing

Predict the number before you run it: smaller than step 2, the same, or zero.

```sh
dry "SELECT * FROM \`$TAXI\` LIMIT 10"
```

```
This query will process 6.97 GB when run.   (7487651196 bytes)
```

**What to notice.** The estimate is identical to step 2, to the byte. `LIMIT` bounds the rows
returned, not the bytes scanned. Every column has been read by the time the limit applies. The
editor's Preview tab is the free way to see ten rows.

### Step 5 · `COUNT(*)` reads no bytes

```sh
dry "SELECT COUNT(*) FROM \`$TAXI\`"
q "SELECT COUNT(*) AS trips FROM \`$TAXI\`"
```

```
This query will process 0.00 GB when run.   (0 bytes)

+----------+
|  trips   |
+----------+
| 36256539 |
+----------+
processed 0.00 GB · billed 0.0 MB · slot time 1.1 s · cache false
```

**What to notice.** BigQuery counted thirty-six million rows and billed nothing, because the count
comes from table metadata. The slot time is not zero. Bytes are what on-demand pricing bills, and
slots are the compute that did the work. Step 8 depends on that distinction.

### Step 6 · Two filters, identical rows

```sh
dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$WILD\`
     WHERE _TABLE_SUFFIX = '2022'"
dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$WILD\`
     WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022"
```

```
This query will process 1.07 GB when run.    (1150274528 bytes)
This query will process 46.61 GB when run.   (50046543960 bytes)
```

**What to notice.** Put the two side by side in the editor and work out the cause before you read
on. The wildcard spans thirteen yearly tables. `_TABLE_SUFFIX` is part of the table name, so the
planner drops twelve tables before reading anything. `pickup_datetime` is a column, so the planner
must read all thirteen tables to learn which rows qualify. The rows are the same, and the bytes are
43.5 times greater. The cost is $0.0065 against $0.28 a run. On a five-minute refresh the column
filter costs about $2,400 a month for the same answer.

Three variants look as if they defeat pruning: `CONCAT(_TABLE_SUFFIX, '') = '2022'`,
`CAST(_TABLE_SUFFIX AS INT64) = 2022` and `_TABLE_SUFFIX LIKE '2022'`. All three still read 1.07 GB,
because BigQuery folds them at plan time.

### Step 7 · Partition and cluster, built live

Build both copies of 2022:

```sh
q "CREATE TABLE \`$DS.trips_2022\` AS
   SELECT vendor_id, pickup_datetime, dropoff_datetime, passenger_count,
          trip_distance, payment_type, fare_amount, tip_amount,
          total_amount, pickup_location_id, dropoff_location_id
   FROM \`$TAXI\`
   WHERE pickup_datetime >= '2022-01-01'
     AND pickup_datetime <  '2023-01-01'"

q "CREATE TABLE \`$DS.trips_2022_part\`
   PARTITION BY DATE(pickup_datetime) CLUSTER BY pickup_location_id AS
   SELECT <the same eleven columns> FROM \`$TAXI\` WHERE <the same year>"
```

```
processed 3.49 GB · billed 3574.0 MB · slot time 229.5 s
processed 3.49 GB · billed 3574.0 MB · slot time 559.7 s
```

Then price and run the same one-week question against each copy:

```sh
dry "SELECT pickup_location_id, COUNT(*) AS trips,
            ROUND(SUM(total_amount), 2) AS revenue
     FROM \`$DS.trips_2022\`
     WHERE pickup_datetime >= '2022-07-04'
       AND pickup_datetime <  '2022-07-11'
       AND pickup_location_id = '132' GROUP BY 1"
```

| | Estimate | Result | Billed | Slot time |
|---|---|---|---|---|
| `trips_2022` | 0.97 GB | 36,718 trips, $2,211,168.26 | 997.0 MB | 9.6 s |
| `trips_2022_part` | 0.02 GB | 36,718 trips, $2,211,168.26 | 17.0 MB | 0.2 s |

Finally, make the partition filter mandatory and try to skip it:

```sh
q "ALTER TABLE \`$DS.trips_2022_part\`
   SET OPTIONS (require_partition_filter = TRUE)"
q "SELECT COUNT(*) AS trips FROM \`$DS.trips_2022_part\`
   WHERE pickup_location_id = '132'"
```

```
Cannot query over table '...trips_2022_part' without a filter over column(s)
'pickup_datetime' that can be used for partition elimination
```

**What to notice.** The two copies hold the same rows and the same 3.49 GB. The partitioned copy
cost 560 slot-seconds to write against 230. That is the price, paid once at write time. The same
answer then bills 997 MB against 17 MB, 58 times less, and the saving recurs on every read. The
estimate reads 0.02 GB because the planner can see the partitions. Clustering removed the last few
megabytes, and only the run can see that effect. The `require_partition_filter` option refuses a
query before it runs. A partitioning scheme that no query filters on saves nothing, and this option
makes forgetting the filter impossible.

### Step 8 · The execution plan is the Dremel model

```sh
q "SELECT pickup_location_id, COUNT(*) AS trips FROM \`$DS.trips_2022\`
   GROUP BY 1 ORDER BY trips DESC LIMIT 5"
plan
```

```
processed 0.16 GB · billed 167.0 MB · slot time 2.2 s

stage          rows in   rows out   shuffle bytes   parallel
S00: Input    36255983      15366          254890         62
S01: Sort+       15366         30             505          6
S02: Output         30          5              85          1
```

Open **Execution details** on the same job in the Console to see the same plan as a graph.

**What to notice.** Dremel, the engine behind BigQuery, runs a query as a tree. Sixty-two leaves
read one column from Colossus, Google's distributed file system, in parallel. Each leaf counts its
own share before anything moves. The shuffle over Jupiter, Google's data-center network, therefore
carries 15,366 partial counts in 254,890 bytes rather than thirty-six million rows. The mixers
combine them, and the root returns five. Slot time is the compute across the whole tree, 2.2 seconds
of it. Bytes processed is what on-demand pricing bills. Under capacity pricing the slot time is the
bill instead, and that is the whole difference between the two models.

### Step 9 · An external table, and an estimate of zero

```sh
gcloud storage ls -l "gs://$BUCKET/trips/2022-01/"
q "CREATE EXTERNAL TABLE \`$DS.trips_ext\`
   OPTIONS (format = 'PARQUET',
            uris = ['gs://$BUCKET/trips/2022-01/*.parquet'])"
for t in trips_ext trips_2022; do
  bq --project_id="$PROJECT" show --format=json "$PROJECT:$DATASET.$t" \
    | jq -c '{table: .tableReference.tableId, type, numRows, numBytes}'
done
dry "SELECT payment_type, COUNT(*) AS trips,
            ROUND(AVG(tip_amount), 2) AS avg_tip
     FROM \`$DS.trips_ext\` GROUP BY 1 ORDER BY trips DESC"
q   "<the same query>"
```

```
TOTAL: 3 objects, 62263753 bytes (59.38MiB)

{"table":"trips_ext","type":"EXTERNAL","numRows":"0","numBytes":"0"}
{"table":"trips_2022","type":"TABLE","numRows":"36255983",
 "numBytes":"3746596329"}

This query will process 0.00 GB when run.   (0 bytes)
processed 0.04 GB · billed 45.0 MB · slot time 1.6 s
```

**What to notice.** The bucket plays the company's raw zone: three Parquet files holding one month
of trips. BigQuery holds a pointer and a schema and nothing else, so it reports zero rows and zero
bytes, and the estimator prices the query at zero. The run then reads the files and bills 45 MB. The
free estimator is blind to external tables. A team that moves data out of native storage loses the
habit step 1 built. No pricing page states that operational cost.

### Step 10 · BigLake, delegation, and a policy tag

Create the governed table over the same files, through the connection:

```sh
q "CREATE EXTERNAL TABLE \`$DS.trips_lake\`
   WITH CONNECTION \`$CONNECTION\`
   OPTIONS (format = 'PARQUET',
            uris = ['gs://$BUCKET/trips/2022-01/*.parquet'])"
```

Then query both tables as the second principal, who holds the dataset and no Cloud Storage access:

```sh
as_analyst q "SELECT COUNT(*) AS trips FROM \`$DS.trips_ext\`"
as_analyst q "SELECT COUNT(*) AS trips FROM \`$DS.trips_lake\`"
```

```
Access Denied: BigQuery BigQuery: Permission denied while globbing
file pattern.
dsba6190-analyst@YOUR_PROJECT_ID.iam.gserviceaccount.com does not have
storage.objects.list access to the Google Cloud Storage bucket.

+---------+
|  trips  |
+---------+
| 2463900 |
+---------+
```

Every `as_analyst` command prints `WARNING: This command is using service account impersonation`.
The warning is expected. It names the principal the query runs as.

Now tag the two location columns and query again:

```sh
bq --project_id="$PROJECT" show --schema --format=json \
     "$PROJECT:$DATASET.trips_lake" \
  | jq --arg tag "$POLICY_TAG" \
       'map(if .name == "pickup_location_id"
               or .name == "dropoff_location_id"
            then . + {policyTags: {names: [$tag]}} else . end)' \
  > "$WORK/schema-tagged.json"
bq --project_id="$PROJECT" update \
  --schema "$WORK/schema-tagged.json" "$PROJECT:$DATASET.trips_lake"

as_analyst q "SELECT * FROM \`$DS.trips_lake\` LIMIT 3"
as_analyst q "SELECT * EXCEPT (pickup_location_id, dropoff_location_id)
              FROM \`$DS.trips_lake\` ORDER BY pickup_datetime LIMIT 3"
q "SELECT pickup_location_id, COUNT(*) AS trips FROM \`$DS.trips_lake\`
   GROUP BY 1 ORDER BY trips DESC LIMIT 3"
```

```
Access Denied: BigQuery BigQuery: User has neither fine-grained
reader nor masked get permission to get data protected by policy
tag "dsba6190-72583 : trip_location" on columns
...trips_lake.dropoff_location_id, ...trips_lake.pickup_location_id.

(three rows, nine columns, no location)
processed 0.22 GB · billed 221.0 MB · slot time 2.8 s

| 237 | 121628 |
| 236 | 120812 |
| 132 | 103485 |
```

The last query runs as the project owner, your own account. The capture files label this principal
`instructor`, as in `34-instructor-tagged.txt`.

**What to notice.** The three results come from three different controls.

**Delegation.** The plain external table runs as the analyst, and the analyst cannot read the
bucket. The BigLake table over the same files reads through the connection's own service account, so
the analyst never needs a storage grant. A governed lakehouse therefore does not grant every analyst
access to every bucket.

**An error, not a null.** The policy tag refuses the whole query and names both columns. A null
would let a query appear to succeed while hiding what was withheld. An error is visible and
auditable. The project owner holds Fine-Grained Reader on the tag and reads the same columns without
complaint. Data masking is the alternative when a column must stay joinable. It returns a hash or a
null instead of an error, and it needs a data policy and a masked-reader grant on top of the tag.

**Why location.** A pickup zone and a timestamp together identify a rider. This is the mosaic
effect, in which fields that are harmless alone identify a person in combination. A column that is
not a name or a number can therefore still be personal data.

The second analyst query also bills 221 MB for three rows, because `ORDER BY` forced a full read.
Step 4 repeats itself on a governed table.

### Step 11 · Row access policies, two principals, one query

```sh
q "CREATE ROW ACCESS POLICY vendor_2 ON \`$DS.trips_lake\`
   GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')"

q "SELECT COUNT(*) AS trips, COUNT(DISTINCT vendor_id) AS vendors,
          STRING_AGG(DISTINCT vendor_id ORDER BY vendor_id) AS vendor_ids
   FROM \`$DS.trips_lake\`"
```

```
+-------+---------+------------+
| trips | vendors | vendor_ids |
+-------+---------+------------+
|     0 |       0 | NULL       |
+-------+---------+------------+
```

Then grant your own account every row, and run the same query as both principals:

```sh
q "CREATE ROW ACCESS POLICY all_rows ON \`$DS.trips_lake\`
   GRANT TO ('user:$ME') FILTER USING (TRUE)"
q "<the same count>"
as_analyst q "<the same count>"
```

```
| 2463900 |       4 | 1,2,5,6    |      project owner
| 1716028 |       1 | 2          |      dsba6190-analyst
```

The capture files `36-instructor-sees-nothing.txt` and `38-instructor-all.txt` hold the project
owner's two counts.

Then try the same control on the plain external table, and list what exists:

```sh
q "CREATE ROW ACCESS POLICY vendor_2 ON \`$DS.trips_ext\`
   GRANT TO ('serviceAccount:$ANALYST') FILTER USING (vendor_id = '2')"
bq --project_id="$PROJECT" ls --row_access_policies \
  "$PROJECT:$DATASET.trips_lake"
```

```
Row access policies are only supported on BigQuery tables, BigLake
external tables,
and BigQuery tables for Apache Iceberg
```

**What to notice.** The owner of the project saw zero rows. **Once any row policy exists, a
principal named in none of them sees nothing**, and ownership exempts no one. One identical query
then returns two different answers, and neither result carries any sign that a filter was applied.
The plain external table cannot hold the control at all. This is the governance boundary between
table types: external tables sit outside it, and BigLake tables sit inside it.

### Step 12 · Teardown

```sh
bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"
bq --project_id="${PROJECT:?}" --location=US \
  rm -f --connection "${CONNECTION:?}"
curl -s -X DELETE \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "x-goog-user-project: ${PROJECT:?}" \
     "https://datacatalog.googleapis.com/v1/${TAXONOMY:?}"
gcloud storage rm -r "gs://${BUCKET:?}"
```

Every name in these four commands is written `${NAME:?}`, so an empty variable refuses to run
instead of deleting the wrong thing. If `env.sh` was never sourced, `"gs://$BUCKET"` expands to
`gs://`, and `gcloud storage rm -r gs://` deletes every bucket in the project.

Then verify. Each command prints a zero:

```sh
bq --project_id="$PROJECT" ls | grep -c "$DATASET"
bq --project_id="$PROJECT" --location=US ls --connection \
  | grep -c "$CONNECTION_ID"
gcloud data-catalog taxonomies list --location us \
  --project "$PROJECT" --format="value(name)" | grep -c .
gcloud storage ls --project "$PROJECT" | grep -c "$BUCKET"
```

**What to notice.** Four resources need four different commands. The dataset takes its four tables
and both row policies with it. The taxonomy needs the REST API, because the gcloud surface for Data
Catalog taxonomies has `import` and `list` and no `delete`. A resource with no obvious delete is the
resource most likely to survive a teardown.

Two things stay by design. The second principal, `dsba6190-analyst`, keeps two grants:
`roles/iam.serviceAccountTokenCreator` for your account on the service account, and
`roles/bigquery.jobUser` on the project. Its dataset grant went with the dataset. A service account
is free, and recreating it costs about five minutes of propagation on the next run. The Data Catalog
API also stays enabled. The next day, open Billing, Reports, filtered to your project and grouped by
service. Expect BigQuery at zero against the free tebibyte, or a few cents if the monthly allowance
is gone, and Cloud Storage at a fraction of a cent.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `Invalid choice: 'create'` on `gcloud data-catalog taxonomies` | The gcloud surface has no `create`. `live-setup.sh` uses `import`, which creates the taxonomy from a JSON file |
| `iam.serviceAccounts.getAccessToken` is denied | The token-creator grant on the second principal has not propagated. Wait two minutes and retry. It took about five minutes the first time |
| The bucket grant to the connection fails with "does not exist" | The connection's service account is created asynchronously. `live-setup.sh` retries for up to three minutes |
| The BigLake table fails with a storage permission error | The connection's service account lacks `roles/storage.objectViewer` on the bucket. Check that `bq show --connection` returns a `serviceAccountId`, then rerun `live-setup.sh` |
| The policy tag attaches but is not enforced | The taxonomy does not have fine-grained access control activated. `live-setup.sh` activates it on import. Check `activatedPolicyTypes` |
| The policy tag will not attach | The taxonomy is in a different location from the dataset. Both must be `us`. The error does not name the region |
| A dry run returns a different number from the recorded figure | The public dataset changed. Compare the ratios, which the argument depends on |
| `q` prints a result but no processed line | The job-statistics call failed. The result is still valid. Read the bytes from Query history in the Console |
| A `CREATE TABLE` in step 7 runs past a minute | The slot pool is busy. Wait for it to finish |
| Credentials expire during the run | Run `gcloud auth login` and continue from the same cell |

---

## Files

| Path | What it is |
|---|---|
| `live-setup.sh` | Stages the dataset, the bucket and its Parquet, the connection, the taxonomy and the second principal. It creates resources and never deletes them |
| `lib.sh` | The four helpers `env.sh` loads: `dry`, `q`, `plan` and `as_analyst` |
| `sql/bytes-scanned.sql` | The cost queries for steps 1 to 6, ready to paste into the BigQuery editor |
| `capture.sh`, `capture/` | The recorder and the real output, one file per command, 47 files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
