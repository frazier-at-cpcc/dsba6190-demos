# Session 7 live demo · runbook

Make the cost visible, then govern it. One hour, twelve steps, 1:30 to 2:30 in the revised session
plan.

Rehearsed end to end on 24 September 2026 against project `YOUR_PROJECT_ID`, BigQuery CLI 2.1.38,
Google Cloud SDK 586.0.0. Every command below was run. Every expected output below is real, and
`capture/` holds the full text of each one.

**Do not run `capture.sh` in class.** It is the headless recorder. It stages its own estate, runs
all twelve steps, and deletes the dataset, the connection, the taxonomy and the bucket through an
exit trap. `live-setup.sh` is its opposite: it provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you want to reproduce it on your own
> Google Cloud account, it costs under **$0.10**, and the first tebibyte of queries each month is
> free, so on a new account it costs nothing. Opening that account requires a credit card at
> signup, though Google does not charge it. That is your choice and no part of this course requires
> it. **Destroy what you create.** The teardown step is the last step for a reason.

The figure covers about 8.5 GB of on-demand scan in the hour, almost all of it the two copies of
2022 built at step 7, and about 3.5 GB in `live-setup.sh` for the Parquet export. At $6.25 per TiB
that is under eight cents. Storage is two 3.5 GB tables and 59 MB of Parquet for about an hour,
which is a fraction of a cent. Steps 1 to 6 are dry runs and cost nothing at all. The figure is an
estimate from list pricing; verify it against Billing the morning after class, as the teardown
checklist asks.

---

## How the hour fits the session clock

The session plan carried this demonstration at twelve minutes inside 1:10 to 1:50. It is now an
hour.

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · How BigQuery actually works | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Governance and cost | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Guided lab · Lab 7, supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

Concept Block 2 keeps fine-grained security, Iceberg and modeling. It hands the whole cost argument
to this hour, where every number is measured rather than asserted.

**The guided lab is a supervised start.** Lab 7 is the Badge 3 guided course and runs about an hour.
Twenty-five minutes starts it, and the part worth starting in the room is the connection and its
grant, because that is where students stall. They have just watched the same connection work at step
10.

---

## The scenario · Queen City Trip Analytics

The hour is taught as one company's work, so that students apply each control to a business rather
than to a dataset. **Queen City Trip Analytics** is fictional: a twelve-person analytics company in
South End, Charlotte, that sells demand and pricing dashboards to ground-transportation fleets. It
uses New York's public trip records as its benchmark market, because that is the largest public trip
dataset available and it lets the company build and price its product before it has Charlotte
customers. It is also the data students use in A7 Part B.

| Step | What it is in the scenario |
|---|---|
| 1 to 6 | The cost of the dashboards the company sells, which refresh every five minutes |
| 7 | The airport product. JFK, zone 132, stands in for Charlotte Douglas |
| 8 | Why the airport query is fast enough to sell |
| 9 | A month of trips kept in the company's raw zone |
| 10 | The analyst at the first fleet customer, who is the second principal. Rider locations are refused |
| 11 | That analyst sees only the customer's trips; Queen City's own analysts see every trip |
| 12 | Closing the demonstration environment |

**One honesty note, say it at step 11.** In the public data, `vendor_id` records the technology
provider that logged a trip. Tonight it stands in for the customer's fleet.

Introduce the company on the scenario slide that precedes the run sheet, in about two minutes, then
open each step with one sentence of what the company is doing. The slide notes carry that sentence.

---

## Two ways to drive the hour

**The notebook.** `demo.ipynb` holds every command below as a cell, in step order, on the Bash
kernel. Open it in VS Code, choose **Select Kernel**, then **Jupyter Kernel**, then **Bash**, and
run one cell at a time. `prep.ipynb` holds the before-class sequence. Neither notebook carries what
to say; this document does.

**The terminal.** Source `env.sh` and type the commands below. Both routes run the same commands.

Steps 1 to 6 are better shown in the BigQuery editor, because the validator in its top right corner
is the thing students use in A7 Part B. `sql/bytes-scanned.sql` holds all eight queries ready to
paste. The notebook runs the same queries as dry runs, which print the same number.

---

## Before class

| Clock | Do | Takes |
|---|---|---|
| T minus 45 | `./live-setup.sh YOUR_PROJECT_ID`, or run `prep.ipynb` | 2 to 7 minutes |
| T minus 38 | `source ~/dsba6190-live-demo-07/env.sh`, run the three checks below | 1 minute |
| T minus 25 | Set up the room | 5 minutes |

### T minus 45 minutes

```sh
cd "lectures/demos/session-07-make-the-cost-visible"
./live-setup.sh YOUR_PROJECT_ID
```

**This script provisions.** It enables five APIs, creates the second principal if it does not exist,
creates the dataset and the bucket, exports one month of 2022 taxi trips to the bucket as Parquet,
creates the BigQuery connection and grants its service account read access to the bucket, imports
the taxonomy with its one policy tag, grants the instructor Fine-Grained Reader on that tag, and
grants the second principal the dataset and nothing else. **It creates no table.** Steps 7, 9, 10
and 11 create every table, the tag attachment and both row policies in front of the room.

**The slow part is IAM.** The first time the second principal was created, its impersonation grant
took about five minutes to propagate. The script blocks until the principal can run a query. On the
rehearsal, with the principal already in place, it was ready in two seconds.

It prints the working directory, the name suffix and every resource name. The default working
directory is `~/dsba6190-live-demo-07`.

```sh
source ~/dsba6190-live-demo-07/env.sh
```

That puts `$PROJECT`, `$DS`, `$BUCKET`, `$CONNECTION`, `$POLICY_TAG`, `$ANALYST`, `$TAXI` and
`$WILD` into the shell, and loads four helpers:

| Helper | What it does |
|---|---|
| `dry "<sql>"` | A dry run. Prints the estimate the editor would show, in GB. Free |
| `q "<sql>"` | Runs the query with the cache off, then prints bytes processed, bytes billed and slot time |
| `plan` | Prints the stages, rows, shuffle bytes and parallelism of the last `q` |
| `as_analyst <command>` | Runs one command as the second principal, through impersonation |

### T minus 38 minutes, verify

```sh
as_analyst q "SELECT SESSION_USER() AS who"
bq --project_id="$PROJECT" --location=US \
  show --connection "$CONNECTION" | head -3
gcloud storage ls "gs://$BUCKET/trips/2022-01/"
```

Expect the second principal's address, the connection, and three Parquet files. If the first command
fails with `iam.serviceAccounts.getAccessToken`, the impersonation grant has not propagated. Wait
two minutes and run it again.

### Common causes, in the order they occur

| Symptom | Cause | Fix |
|---|---|---|
| `Invalid choice: 'create'` on `gcloud data-catalog taxonomies` | There is no `create` in the gcloud surface. The script uses `import`, which creates from a JSON file | Use the script. Do not improvise the taxonomy |
| `iam.serviceAccounts.getAccessToken` denied | The token-creator grant on the second principal has not propagated | Wait. It took about five minutes the first time |
| Any `as_analyst` command prints `WARNING: This command is using service account impersonation` | This is expected, not an error | Read it aloud once. It names the principal the query runs as |
| BigLake table fails with a storage permission error | The connection's service account lacks `roles/storage.objectViewer` on the bucket | The script grants it. Check `bq show --connection` returns a `serviceAccountId` |
| Policy tag attaches but is not enforced | The taxonomy does not have fine-grained access control activated | The script activates it on import. Check `activatedPolicyTypes` |
| Policy tag will not attach | The taxonomy is in a different location from the dataset | Both are `us`. A region mismatch produces an error that does not name the region |

### Set up the room

- The BigQuery editor open in the demo project, with `sql/bytes-scanned.sql` in a second tab.
- `demo.ipynb` open on the Bash kernel, with the first cell run, or a terminal with `env.sh`
  sourced. Enlarge the font until the back row can read a byte count.
- Deck on slide 31, the Live Demonstration divider, with the Queen City scenario on 32, the run
  sheet on 33 and 34, and the twelve capture slides at 35 to 46.
- The Hour 1 storage and compute drawing still on the board. Step 8 points back at it.

**Network contingency.** If the room has no working connection, present from the deck. Slides 35 to
46 carry one step each, trimmed to the type floor, and the full text of every command is in
`capture/`. Every file in it is real output from the 24 September rehearsal, one file per command,
numbered in the order below. Say plainly that the output is recorded.

---

## The sequence

Every command runs from the shell that sourced `env.sh`, or from the matching cell in `demo.ipynb`.
The captured outputs below carry the rehearsal suffix `72583`.

| # | Step | Minutes |
|---|---|---|
| 1 | The estimator prices a query before it runs | 3 |
| 2 | `SELECT *`, and the number to beat | 4 |
| 3 | Three named columns | 4 |
| 4 | `LIMIT 10` changes nothing | 4 |
| 5 | `COUNT(*)` reads no bytes | 3 |
| 6 | Two filters, identical rows | 6 |
| 7 | Partition and cluster, built live | 7 |
| 8 | The execution plan is the Dremel model | 6 |
| 9 | An external table, and an estimate of zero | 6 |
| 10 | BigLake, delegation, and a policy tag | 7 |
| 11 | Row access policies, two principals, one query | 6 |
| 12 | Teardown | 3 |
| | **Total** | **59** |

### Step 1 · The estimator prices a query before it runs · 3 minutes

In the BigQuery editor, paste query 3 from `sql/bytes-scanned.sql` and do not press Run. Point at
the validator: "This query will process 1.07 GB when run." Then the terminal form:

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
engine in this course does that. A7 Part B is built on this habit, and it is why Part B costs a
student nothing.

### Step 2 · `SELECT *`, and the number to beat · 4 minutes

```sh
dry "SELECT * FROM \`$TAXI\`"
```

```
This query will process 6.97 GB when run.   (7487651196 bytes)
```

**What to notice.** Write **6.97 GB** on the board. At $6.25 per TiB this query costs about four
cents. Multiply it before moving on: a dashboard tile on a five-minute refresh runs it 8,640 times a
month, which is about $370 for one tile.

### Step 3 · Three named columns · 4 minutes

```sh
dry "SELECT pickup_datetime, passenger_count, fare_amount FROM \`$TAXI\`"
dry "SELECT AVG(fare_amount) FROM \`$TAXI\`"
```

```
This query will process 1.07 GB when run.   (1150274528 bytes)
This query will process 0.54 GB when run.   (580104624 bytes)
```

**What to notice.** Say the ratio out loud: 6.5 times less for a one-line edit. The second query
halves it again because it reads one column. The average costs nothing to compute. Columnar storage
bills per column touched, which is the Colossus drawing from Hour 1 turned into a price.

### Step 4 · `LIMIT 10` changes nothing · 4 minutes

Ask the room to predict first. Take a show of hands on smaller, the same, and zero.

```sh
dry "SELECT * FROM \`$TAXI\` LIMIT 10"
```

```
This query will process 6.97 GB when run.   (7487651196 bytes)
```

**What to notice.** Identical to step 2, to the byte. `LIMIT` bounds the rows returned, not the
bytes scanned. Every column has been read by the time the limit applies. This is the most common
mistake in A7 Part B and a reliable midterm item. The editor's Preview tab is the free way to see
ten rows.

### Step 5 · `COUNT(*)` reads no bytes · 3 minutes

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

**What to notice.** Thirty-six million rows counted and nothing billed, because the count comes from
table metadata. The slot time is not zero. Bytes are what on-demand pricing bills, and slots are the
compute that did the work. Step 8 depends on that distinction, so name it here. The A9 Part B
callback: DuckDB answers the same question over Parquet in about a millisecond, for the same reason.

### Step 6 · Two filters, identical rows · 6 minutes

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

**What to notice.** This is the payload of the cost half. Put the two side by side in the editor and
ask why before explaining. The wildcard spans thirteen yearly tables. `_TABLE_SUFFIX` is part of the
table name, so the planner drops twelve tables before reading anything. `pickup_datetime` is a
column, so the planner must read all thirteen to learn which rows qualify. Same rows, 43.5 times the
bytes: $0.0065 against $0.28 a run, and on a five-minute refresh about $2,400 a month for the same
answer.

Do not demonstrate `CAST(_TABLE_SUFFIX AS INT64) = 2022` or its relatives. They still prune, and
they turn a lesson into a detour. `sql/bytes-scanned.sql` records why.

### Step 7 · Partition and cluster, built live · 7 minutes

Build both copies, and talk through the second while it runs.

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

Then the same one-week question against each copy, priced first and then run:

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

**What to notice.** Three things, in order. The two copies are the same rows and the same 3.49 GB,
and the partitioned one cost 560 slot-seconds to write against 230. That is the price, paid once at
write time. The same answer then bills 997 MB against 17 MB, 58 times less, collected on every read.
The estimate reads 0.02 GB because the planner can see the partitions; the last few megabytes came
off through clustering, which only the run can see. And `require_partition_filter` refuses a query
before it runs, which is the Lab 7 watch-for performed. A partitioning scheme nobody filters on
saves nothing; this option makes forgetting impossible.

### Step 8 · The execution plan is the Dremel model · 6 minutes

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

Open **Execution details** on the same job in the Console as well. The graph reads better from the
back row than the table does.

**What to notice.** Point at the Hour 1 drawing and walk the tree. Sixty-two leaves read one column
from Colossus in parallel. Each leaf counts its own share before anything moves, so the shuffle over
Jupiter carries 15,366 partial counts in 254,890 bytes rather than thirty-six million rows. The
mixers combine them and the root returns five. Slot time is the compute across the whole tree, 2.2
seconds of it. Bytes processed is what on-demand pricing bills. Under capacity pricing the slot time
is the bill instead, which is the whole difference between the two models.

### Step 9 · An external table, and an estimate of zero · 6 minutes

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

**What to notice.** The bucket is the raw zone from Week 5: three Parquet files, one month of trips.
BigQuery holds a pointer and a schema and nothing else, so it reports zero rows and zero bytes, and
the estimator prices the query at zero. The run then reads the files and bills 45 MB. **The free
estimator is blind to external tables.** A team that moves data out of native storage loses the
habit step 1 built, and that is an A7 argument about operational cost that no pricing page states.

### Step 10 · BigLake, delegation, and a policy tag · 7 minutes

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

**What to notice.** Three results, and each one is a different control.

**Delegation.** The plain external table runs as the analyst, and the analyst cannot read the
bucket. The BigLake table over the same files reads through the connection's own service account, so
the analyst never needs a storage grant. That is why a governed lakehouse does not grant every
analyst on every bucket.

**An error, not a null.** The policy tag refuses the whole query and names both columns. A null
would let a query appear to succeed while hiding what was withheld; an error is visible and
auditable. The instructor, who holds Fine-Grained Reader on the tag, reads the same columns without
complaint.

**Why location.** A pickup zone and a timestamp together identify a rider. That is the mosaic effect
from Week 5, and it is why a column that is not a name or a number can still be personal data.

And name the side lesson in the second analyst query: it bills 221 MB for three rows, because `ORDER
BY` forced a full read. Step 4 again, on a governed table.

### Step 11 · Row access policies, two principals, one query · 6 minutes

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

Let that sit. Then grant the instructor every row, and run the same query as both principals:

```sh
q "CREATE ROW ACCESS POLICY all_rows ON \`$DS.trips_lake\`
   GRANT TO ('user:$ME') FILTER USING (TRUE)"
q "<the same count>"
as_analyst q "<the same count>"
```

```
| 2463900 |       4 | 1,2,5,6    |      instructor
| 1716028 |       1 | 2          |      dsba6190-analyst
```

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
principal named in none of them sees nothing**, and ownership does not exempt anyone. Then one
identical query returns two different answers, and neither result carries any sign that a filter was
applied. The regional analyst from the concept block sees only their region without knowing a filter
exists. And the plain external table cannot hold the control at all, which is the governance
boundary the Hour 1 table-type slide drew: external tables sit outside it and BigLake tables sit
inside.

### Step 12 · Teardown · 3 minutes

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

**Every name in these four commands is written `${NAME:?}`, and that is not decoration.** If
`env.sh` was never sourced, `"gs://$BUCKET"` expands to `gs://`, and `gcloud storage rm -r gs://`
deletes every bucket in the project. That happened during the rehearsal of this demonstration on 24
September 2026, when a failed `live-setup.sh` left the names empty and a teardown cell ran anyway.
Seven unrelated buckets were deleted, and all seven were restored from soft delete. The `:?` form
refuses to run with an empty name.

Then verify, which should print four zeros:

```sh
bq --project_id="$PROJECT" ls | grep -c "$DATASET"
bq --project_id="$PROJECT" --location=US ls --connection \
  | grep -c "$CONNECTION_ID"
gcloud data-catalog taxonomies list --location us \
  --project "$PROJECT" --format="value(name)" | grep -c .
gcloud storage ls --project "$PROJECT" | grep -c "$BUCKET"
```

**What to notice.** Four resources, four different commands. The dataset takes its tables and both
row policies with it. The taxonomy needs the REST API, because the gcloud surface for Data Catalog
taxonomies has `import` and `list` and no `delete`. A resource with no obvious delete is exactly the
resource that survives a teardown.

---

## What the hour skips

Nothing the plan asked for. Two things are deliberately left out.

| Left out | Why |
|---|---|
| Data masking, which returns a hash or a null instead of an error | It needs a data policy and a masked-reader grant on top of the tag, and it would blur step 10's point that the unmasked control is an error. Name it as the alternative when a column must stay joinable |
| The three `_TABLE_SUFFIX` variants that look as if they defeat pruning | They do not. All three still read 1.07 GB. `sql/bytes-scanned.sql` records them so nobody retries them live |

---

## Teardown

Step 12 performs this in front of the room. Run the checks again after class if the hour stopped
early.

- [ ] **Destroy by the mechanism that created it.** There is no Terraform in this demonstration.
      `live-setup.sh` printed the four commands, and step 12 runs them.
- [ ] **BigQuery.** Dataset `dsba6190_wh_<SUFFIX>` dropped, with its four tables and two row
      policies. `bq --project_id=YOUR_PROJECT_ID ls` should list only `analytics_demo`, a
      pre-existing dataset this demonstration does not touch.
- [ ] **Connection.** `dsba6190-lake-<SUFFIX>` deleted. A connection costs nothing, and it still holds
      a service account with read access to a bucket.
- [ ] **Catalog.** Taxonomy `dsba6190-<SUFFIX>` deleted, which removes its policy tag and the
      instructor's grant on it. `gcloud data-catalog taxonomies list --location us` should answer
      `Listed 0 items.`
- [ ] **Storage.** Bucket `dsba6190-trips-<SUFFIX>` deleted. No retention policy is set, so nothing
      is refused.
- [ ] ~~**Compute, streaming, serving, registry, keys.**~~ None is created.
- [ ] **Verify against billing, next morning.** Billing, Reports, filtered to the demo project,
      grouped by service, for yesterday. Expect BigQuery at zero against the free tebibyte, or a few
      cents if the month's allowance is gone, and Cloud Storage at a fraction of a cent.
- [ ] **What stays by design.** The second principal, `dsba6190-analyst`, with two grants:
      `roles/iam.serviceAccountTokenCreator` for the instructor on the account, and
      `roles/bigquery.jobUser` on the project. Its dataset grant went with the dataset. A service account is free, and recreating it costs
      five minutes of propagation on the next run. The Data Catalog API stays enabled.

---

## If it fails live

| What happened | Do this |
|---|---|
| `as_analyst` fails with `getAccessToken` | The grant has not propagated. Present steps 10 and 11 from slides 44 and 45 and say so. It is IAM propagation, the Week 2 lesson returning |
| A dry run returns a different number from the slide | The public dataset changed. Say so, read the new number, and use the ratio, which is what the argument depends on |
| `q` prints a result but no processed line | The job-stats call failed. The result is still valid. Read bytes from Query history in the Console |
| Step 7's `CREATE TABLE` runs past a minute | The slot pool is busy. Keep talking. If it passes three minutes, present slide 41 and skip to step 8 against the public table |
| BigLake query fails with a storage error for the instructor | The connection's grant is missing. Present slides 44 and 45. Do not debug the grant in front of the room |
| Credentials expired mid-session | `gcloud auth login`, or move to `capture/` and say the output is recorded |
| The hour runs out at step 10 | Skip step 11's external-table refusal, keep the two-principal count, and run the teardown. Never leave the connection holding a storage grant overnight |

---

## What is staged where

| Path | Step | What it is |
|---|---|---|
| `env.sh` | all | The names, and the four helpers from `lib.sh` |
| `lib.sh` | all | `dry`, `q`, `plan`, `as_analyst` |
| `sql/bytes-scanned.sql` | 1 to 6 | The eight queries, ready to paste into the editor, with the figures measured on 15 August and re-measured on 24 September |
| `gs://dsba6190-trips-<SUFFIX>/trips/2022-01/` | 9 to 11 | January 2022, 2,463,900 trips, three Parquet files, 59 MB |
| `dsba6190-lake-<SUFFIX>` connection | 10 | Holds `roles/storage.objectViewer` on the bucket |
| taxonomy `dsba6190-<SUFFIX>`, tag `trip_location` | 10 | Fine-grained access control activated, instructor granted |
| `dsba6190-analyst` | 10, 11 | Dataset viewer, job user, no storage, no tag |

---

## Where the captured output is on the deck

The deck carries a Live Demonstration divider, a twelve-step run sheet, and one capture slide per
step, each a listing of real output trimmed to the type floor, with the capture date and the source
files named in its speaker notes. Slide numbers are counted from the built deck, not from the
AsciiDoc headings.

Slide 31 is the `Live Demonstration` divider, slide 32 introduces Queen City Trip Analytics, and
slides 33 and 34 carry the run sheet, which the converter splits in two. The deck runs to 61 slides
since the A7 scaffolding was added on 27 September.

| Step | Deck slide | Captures authored onto it |
|---|---|---|
| 1 | 35 | `01-dry-run-native.txt`, `02-table-size.txt` |
| 2 | 36 | `03-select-star.txt` |
| 3 | 37 | `04-three-columns.txt`, `05-one-column.txt` |
| 4 | 38 | `06-limit-10.txt` |
| 5 | 39 | `07-count-dry.txt`, `08-count-run.txt` |
| 6 | 40 | `09-wildcard-suffix.txt`, `10-wildcard-column.txt` |
| 7 | 41 | `13-two-copies.txt`, `16` and `17`, `19-require-filter-refused.txt`, condensed |
| 8 | 42 | `20-groupby-run.txt`, `21-plan.txt` |
| 9 | 43 | `24-external-no-stats.txt`, `25-external-dry.txt`, `26-external-run.txt` |
| 10 | 44 | `28` and `29`, `32-analyst-select-star.txt`, errors trimmed |
| 11 | 45 | `35` to `39`, condensed |
| 12 | 46 | `42` to `46` |

The masked values stay masked. `capture.sh` replaces the authenticated account with
`instructor@example.edu` and the project number with `PROJECT_NUMBER`.
