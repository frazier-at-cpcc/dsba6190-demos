# Session 6 walkthrough · A batch pipeline, then break it

This walkthrough builds one batch pipeline in Cloud Data Fusion, breaks it twice, and repairs it in
twelve steps, in `us-central1`. Every command below was run end to end on 10 September 2026 against
Cloud Data Fusion 6.11.1 Basic edition, Google Cloud SDK 584.0.0, `google-cloud` 0.24.1,
`wrangler-transform` 4.11.1 and `core-plugins` 2.13.1. `capture/` holds the full output of each
command. You can read the walkthrough and the captures without running anything. No Terraform is
used. The artifact is the pipeline, and a Data Fusion pipeline is a JSON document.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run consumed 1.22 instance-hours of Basic-edition Data Fusion across
> seven pipeline runs. Following the notebooks by hand takes two to three instance-hours, about $4.
> Basic edition bills $1.80 per instance-hour from creation, and the first 120 instance-hours each
> month are free per billing account. Each pipeline run adds an ephemeral three-node Dataproc
> cluster at about $0.04. Storage and queries cost less than a cent. An instance left running
> costs $25.20 for one night and $1,296 for a month. Delete it the same day, in the order the
> teardown section shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Crown Street Markets

**Crown Street Markets** is a fictional grocery chain with 40 stores across Mecklenburg County,
headquartered in Charlotte. Every night each store's register system drops a point-of-sale extract
into Cloud Storage. A three-person analytics team turns it into the validated sales table that store
managers read at 7 a.m. Tonight's file is one business day: 20,000 transactions from stores
`CLT-001` to `CLT-040`.

| Step | What it is in the scenario |
|---|---|
| 1 to 5 | Building the pipeline that produces the store managers' morning table |
| 6 | The control numbers: one sales day across forty stores |
| 7 and 8 | A register software update sends three rows it should not have sent |
| 9 | The morning report shows the day twice, and two transactions are gone without a trace |
| 10 and 11 | Finance can reconcile the day, and the quarantined rows name their stores and reasons |
| 12 | The 3 a.m. rerun that fails for a reason unrelated to the data |

---

## Before you start

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-06/env.sh
python3 cdap.py artifacts --endpoint "$ENDPOINT"
```

You need the beta `gcloud` components, because every command is `gcloud beta data-fusion`. Install
them with `gcloud components install beta`. The notebooks need the Bash kernel. In VS Code, choose
**Select Kernel**, **Jupyter Kernel**, **Bash**.

`live-setup.sh` enables four APIs, creates the Data Fusion instance and waits until it reports
`RUNNING`. It also makes the IAM grants a pipeline run needs, creates the bucket and the BigQuery
dataset, generates the two extracts, uploads the clean one, and writes the four pipeline definitions
against the plugin versions the instance carries. It deploys nothing and runs nothing. It prints a
name suffix, every resource name, the Studio URL and the teardown commands. `env.sh` exports
`$PROJECT`, `$INSTANCE`, `$BUCKET`, `$DATASET`, `$FQ` and `$ENDPOINT`, so no command below needs a
name typed by hand.

Instance creation takes about sixteen minutes. The recorded run measured 15 minutes 20 seconds from
`create` to `RUNNING`, and an earlier build measured 16 minutes 46 seconds. On that earlier build,
two create attempts aborted after three seconds before the third succeeded. Google's documentation
states about ten minutes. Allow at least thirty minutes for staging.

The `artifacts` command should print four rows:

```
cdap-data-pipeline       6.11.1       SYSTEM
core-plugins             2.13.1       SYSTEM
google-cloud             0.24.1       SYSTEM
wrangler-transform       4.11.1       SYSTEM
```

An empty answer means the instance reports `RUNNING` but its API is not serving yet. Wait two
minutes and try again.

Then run one pipeline and discard it. Both IAM failure modes appear only when a pipeline runs, so a
smoke run proves the grants before step 4 depends on them.

```sh
python3 cdap.py deploy --endpoint "$ENDPOINT" --app smoke \
  --file "$WORK/pipelines/01-baseline.json"
SMOKE=$(python3 cdap.py start --endpoint "$ENDPOINT" --app smoke)
python3 cdap.py wait --endpoint "$ENDPOINT" --app smoke --run "$SMOKE"

python3 cdap.py delete --endpoint "$ENDPOINT" --app smoke
bq --project_id="${PROJECT:?}" rm -f -t "${DATASET:?}.sales_validated"
gcloud dataproc clusters list --project "$PROJECT" --region us-central1
```

A run takes seven and a half to nine and a half minutes. Let the smoke run finish. A run stopped
between `PENDING` and `RUNNING` can leave its Dataproc cluster behind. A run that reaches `STARTING`
has cleared every permission the demonstration needs. A run that fails in `PENDING` after about five
seconds is missing a grant, and the known-issues table names the fix. The last command must answer
`Listed 0 items.` The smoke run costs about four cents.

Open the Studio URL from `$CONSOLE` in the browser profile that matches `gcloud config get-value
account`. Keep a second tab on the Console at Dataproc, Clusters, for step 4.

---

## The sequence

A pipeline run takes seven and a half to nine and a half minutes. The three successful runs measured
454, 533 and 571 seconds. Most of each run is the queue and the cluster build rather than the work.
The notebooks therefore start runs A, B, C and D at steps 4, 7, 10 and 12, and the step after each
start reads while the run works. Keep the order, because each run leaves the table the next step
reads. Substitute the suffix `live-setup.sh` printed wherever `<SUFFIX>` appears. The captures carry
`75439`, the recorded run's suffix.

| # | Step |
|---|---|
| 1 | The instance, the edition, and the meter |
| 2 | The recipe is a directive list |
| 3 | Three nodes, two edges |
| 4 | Deploy and run, run A |
| 5 | What one run provisions, and what it costs |
| 6 | The control number |
| 7 | The malformed day arrives, run B |
| 8 | Retry, quarantine, halt |
| 9 | One query, two defects |
| 10 | The fix is two properties, run C |
| 11 | Field-level lineage, then the count that reconciles |
| 12 | Change nothing, run it again, run D |

### Step 1 · The instance, the edition, and the meter

```sh
gcloud beta data-fusion instances describe "$INSTANCE" \
  --project "$PROJECT" --location us-central1 \
  --format="yaml(name,state,type,version,apiEndpoint)"
```

The recorded run returned `state: RUNNING`, `type: BASIC` and `version: 6.11.1`. The instance
reached `RUNNING` **920 seconds** after `create`. **What to notice.** The instance has billed since
the moment it was created, whether or not a pipeline ever runs. Data Fusion's real price is the
standing cost of having the platform available, not the price of a run. The sixteen-minute build is
a second cost, paid in lead time.

### Step 2 · The recipe is a directive list

In the Studio, open **Wrangler**, connect to Cloud Storage, and load
`gs://dsba6190-pos-<SUFFIX>/raw/pos/pos-2026-09-24.csv`. Build the recipe by clicking:

1. Parse the body as CSV, first row as header.
2. Drop `body` and `offset`.
3. Rename the six columns.
4. Set `qty` to integer and `amount` to double.
5. Parse `txn_ts` as a datetime with the pattern `yyyy-MM-dd HH:mm:ss`, then convert it to a
   timestamp.

The recipe panel then reads:

```
parse-as-csv :body ',' true
drop :body
drop :offset
rename body_1 txn_id
rename body_2 store_id
rename body_3 txn_ts
rename body_4 sku
rename body_5 qty
rename body_6 amount
set-type :qty integer
set-type :amount double
parse-as-datetime :txn_ts 'yyyy-MM-dd HH:mm:ss'
datetime-to-timestamp :txn_ts
```

**What to notice.** Thirteen clicks produced thirteen lines of code, and the lines are the artifact.
A recipe can be reviewed in a pull request, diffed between versions, and pasted into another
workspace. The recipe is also CDAP's directive language, which runs only in Data Fusion. An Airflow
DAG is open-source Python and runs on any Airflow host. The two `set-type` lines and the
`parse-as-datetime` line are the three directives that can fail on a row.

### Step 3 · Three nodes, two edges

On the canvas, a **GCS** source feeds the **Wrangler** transform, which feeds a **BigQuery** sink.
Read the pipeline back as the document it is:

```sh
SHAPE='(.config.stages[] | "\(.name)\t\(.plugin.type)\t\(.plugin.name)"),
       (.config.connections[] | "\(.from)\t->\t\(.to)")'
jq -r "$SHAPE" "$WORK/pipelines/01-baseline.json" | column -t -s $'\t'
```

The recorded shape, in `capture/07-pipeline-shape.txt`, lists three stages and two connections:

```
stages
  PointOfSaleRaw         batchsource      GCSFile
  Wrangler               transform        Wrangler
  SalesValidated         batchsink        BigQueryTable

connections
  PointOfSaleRaw         -> Wrangler
  Wrangler               -> SalesValidated
```

**What to notice.** The source reads `raw/`, the immutable zone from Session 5, and nothing writes
back into it. That property lets you re-run a wrong pipeline against unchanged source. Three nodes
and two edges form a directed acyclic graph. A pipeline's DAG is the stages of one data movement. An
orchestrator's DAG is many movements in order.

### Step 4 · Deploy and run, run A

```sh
python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-01-baseline \
  --file "$WORK/pipelines/01-baseline.json"
RUN_A=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline)
gcloud dataproc clusters list --project "$PROJECT" --region us-central1 \
  --format="table(clusterName,status.state,config.masterConfig.machineTypeUri.basename(),config.workerConfig.numInstances,config.workerConfig.machineTypeUri.basename())"
```

The deploy reports three stages and two edges. About two and a half minutes into the run, the
cluster list showed one cluster in `CREATING`, with an `e2-custom-2-8192` master and **two
`e2-custom-2-8192` workers**. **What to notice.** Data Fusion created a three-node Dataproc cluster
to run one pipeline over a file of about one megabyte, and it deletes the cluster when the run ends.
The instance-hour buys the Studio, the connectors, lineage and the scheduler. The cluster reads the
bytes, and it bills separately, per run, for as long as the run takes.

### Step 5 · What one run provisions, and what it costs

```sh
python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN_A"
```

| Phase | Recorded run | What is happening |
|---|---|---|
| `PENDING` | 0 to 189 s | The request is queued against the instance |
| `STARTING` | 189 to 299 s | Dataproc is building the cluster |
| `RUNNING` | 299 to 455 s | Spark reads, transforms and writes |
| `COMPLETED` | 455 s | The cluster is deleted |

The run's recorded duration was **454 seconds**. **What to notice.** Two and a half minutes of Spark
processed 20,000 rows, after five minutes of waiting for somewhere to run. This architecture suits
batch work and does not suit anything that must be fresh within minutes. Three `e2-custom-2-8192`
nodes cost about $0.20 an hour together, and the Dataproc surcharge adds about $0.06 an hour, so a
ten-minute run costs about **$0.04**. The runs are nearly free, and the availability is not. A team
running two hundred pipelines a day amortizes the instance. A team running one pipeline a week pays
$1,296 a month for a Studio it opens once a week.

### Step 6 · The control number

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded, ROUND(SUM(amount), 2) AS total_amount,
          COUNTIF(txn_ts IS NULL) AS null_ts
   FROM \`$FQ\`"
```

```
+-------------+--------------+---------+
| rows_loaded | total_amount | null_ts |
+-------------+--------------+---------+
|       20000 |   2422034.45 |       0 |
+-------------+--------------+---------+
```

**What to notice.** Record **20,000** and **2,422,034.45**. They are the control numbers for steps
9, 11 and 12. Every row that left the file arrived in the table, no timestamp is null, and a finance
team could reconcile the total against another system. The source stage read 20,001 records, because
the header line is a record too.

### Step 7 · The malformed day arrives, run B

The source system sends a file with three rows it should not have sent. Put it in place of the clean
file, under the same object key, as a real ingest does.

```sh
gcloud storage cp "$WORK/sample/pos-2026-09-24-dirty.csv" \
  "gs://$BUCKET/raw/pos/pos-2026-09-24.csv"
tail -3 "$WORK/sample/pos-2026-09-24-dirty.csv"
RUN_B=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline)
```

```
T-0900001,CLT-007,not-a-date,SKU-01042,2,18.50
T-0900002,CLT-013,2026-09-24 11:04:22,SKU-01077,1,N/A
T-0900003,CLT-022,2026-09-24 15:41:09,SKU-01003,-4,62.00
```

The object is now 1,131,286 bytes, 158 bytes larger than the clean file. **What to notice.** No
pipeline, schema or recipe changed. Only the file changed, and it changed the way real source data
changes: quietly, under the same name, between two runs.

### Step 8 · Retry, quarantine, halt

```sh
python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-01-baseline --run "$RUN_B"
```

Run B took **571 seconds** and completed. While it works, consider the three designed failure paths
for a bad input.

| Path | When | What it does |
|---|---|---|
| **Retry** | Transient. Network, throttling, a busy endpoint | Back off and try again. It is safe only if the task is idempotent |
| **Quarantine** | Bad data. One row is wrong and the rest are fine | Route the row to a dead-letter path and keep going |
| **Halt** | Systemic. Schema violation, authentication failure, missing source | Stop and alert a person |

A fourth path is **silent coercion**, where a bad value is dropped or cast to null and the run
reports success. It produces no alert, no failed run and no red node on the canvas. **What to
notice.** The baseline Wrangler node sets `on-error` to `skip-error`, which is the default and is
the closest of the settings to silent coercion. Predict the row count before step 9 reads it.

### Step 9 · One query, two defects

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"
python3 cdap.py stages --endpoint "$ENDPOINT" --app pos-01-baseline \
  --run "$RUN_B" --stage Wrangler
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT txn_id, txn_ts, qty, amount FROM \`$FQ\`
   WHERE txn_id IN ('T-0900001','T-0900002','T-0900003') ORDER BY txn_id"
```

```
+-------------+
| rows_loaded |
+-------------+
|       40001 |
+-------------+

Wrangler               records in       20004
Wrangler               records out      20001

+-----------+---------------------+-----+--------+
|  txn_id   |       txn_ts        | qty | amount |
+-----------+---------------------+-----+--------+
| T-0900003 | 2026-09-24 15:41:09 |  -4 |   62.0 |
+-----------+---------------------+-----+--------+
```

**What to notice.** One query reveals two unrelated defects. First, the table holds **40,001** rows.
The pipeline appends, so run A's 20,000 rows remain and run B added 20,001. The pipeline is not
idempotent, and a retry policy on it would produce duplicates. Second, three records entered
Wrangler and did not leave. One is the header line. The other two are `not-a-date`, which failed the
datetime parse, and `N/A`, which failed the cast to double. `skip-error` discarded both with no
warning and no log line, and the run reported success. The third bad row loaded. A quantity of
**-4** is well typed and wrong, and no schema or cast catches it. A type system is not a quality
gate. Only a business rule that forbids a negative quantity catches this row.

### Step 10 · The fix is two properties, run C

```sh
diff <(jq -r "$SHAPE" "$WORK/pipelines/01-baseline.json") \
     <(jq -r "$SHAPE" "$WORK/pipelines/02-quarantine.json") \
  | grep '^>' | column -t -s $'\t'
bq --project_id="${PROJECT:?}" rm -f -t "${DATASET:?}.sales_validated"
python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-02-quarantine \
  --file "$WORK/pipelines/02-quarantine.json"
RUN_C=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine)
```

The recorded diff, in `capture/20-quarantine-shape.txt`, shows two added stages and two added edges.
It also shows Wrangler's `on-error` changing from `skip-error` to `send-to-error-port`:

```
added stages
  QuarantineCollector    errortransform   ErrorCollector
  QuarantineSink         batchsink        GCS

added edges
  Wrangler               -> QuarantineCollector
  QuarantineCollector    -> QuarantineSink
```

To build the same branch on the canvas, set Wrangler's error handling to **send to error port**, add
an **Error Collector**, connect Wrangler's error port to it, and connect the collector to a **GCS**
sink that writes to `gs://dsba6190-pos-<SUFFIX>/quarantine/pos`. The deploy reports five stages and
four edges. **What to notice.** The table is dropped by hand first. Dropping the table is a
workaround, not a fix, and it leaves the idempotency defect in place. The quarantine branch and
idempotency are separate problems with separate solutions. Wrangler already knew the two rows were
bad, and `skip-error` discarded that knowledge. The branch detects nothing new. It stops discarding
what was already detected.

### Step 11 · Field-level lineage, then the count that reconciles

While run C works, open the **Lineage** tab on the deployed pipeline, choose the `amount` field, and
walk it back from the BigQuery column to the CSV column it came from. The recorded lineage lists six
fields, and every one carries recorded lineage.

```sh
python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN_C"
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"
gcloud storage cat "gs://$BUCKET/quarantine/pos/**" | head -4
```

Run C took **533 seconds**. The table holds **20,001** rows, and the quarantine prefix holds two
records:

```
{"offset":1131128,"body":"T-0900001,CLT-007,not-a-date,SKU-01042,2,18.50",
 "errMsg":"Value not-a-date for column txn_ts is not in expected format yyyy-MM-dd HH:mm:ss
 (ecode: 2, directive: parse-as-datetime)","errCode":2,"errStage":"Wrangler"}
{"offset":1131175,"body":"T-0900002,CLT-013,2026-09-24 11:04:22,SKU-01077,1,N/A",
 "errMsg":"Error encountered while executing 'set-type' : Column 'amount' cannot be converted
 to a 'double'.","errCode":0,"errStage":"Wrangler"}
```

**What to notice.** 20,001 loaded plus 2 quarantined equals the 20,003 rows in the file, so the
count reconciles. Each quarantined record carries the original row, its byte offset in the source
file, the stage that rejected it, and the directive that raised the error. In step 9 the same
information existed and was discarded. Lineage shows where `amount` came from, but it records what
the pipeline did, not whether the result is correct. The 1 in 20,001 is the negative quantity, which
is still in the table. The branch handles the rows the pipeline knew were bad and does nothing for
the row it never suspected.

### Step 12 · Change nothing, run it again, run D

```sh
RUN_D=$(python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine)
python3 cdap.py wait --endpoint "$ENDPOINT" --app pos-02-quarantine --run "$RUN_D"
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \`$FQ\`"
python3 cdap.py logs --endpoint "$ENDPOINT" --app pos-02-quarantine \
  --run "$RUN_D" --grep FileAlreadyExists --tail 1
```

```
      0s  PENDING
    172s  STARTING
    282s  RUNNING
    392s  FAILED
```

The table still holds **20,001** rows and 20,001 distinct transactions. The log names the cause:

```
Stage 'QuarantineSink' encountered :
org.apache.hadoop.mapred.FileAlreadyExistsException:
Output directory gs://dsba6190-pos-<SUFFIX>/quarantine/pos already exists
```

**What to notice.** The pipeline cannot run a second time at all. The error sink wrote a directory
on the first run, and a Hadoop output committer refuses to write into a directory that already
exists. Idempotency is a property of every sink in a pipeline, not of the pipeline as a whole. The
BigQuery sink would have appended and doubled the day, and the Cloud Storage sink refused to run.
The quarantine branch that made the count reconcile also made the pipeline unable to run twice. The
fix has two halves:

```
SalesValidated   truncateTable  'false' -> 'true'
QuarantineSink   path  gs://.../quarantine/pos
                    -> gs://.../quarantine/pos/dt=${logicalStartTime(yyyy-MM-dd-HHmmss)}
```

The BigQuery sink replaces the day instead of appending to it. The error sink writes a new
run-scoped prefix instead of one fixed directory. `pipelines/03-idempotent.json` carries both
changes. A retry on a task that cannot succeed twice fails identically, so a retry is safe only when
the task is idempotent.

---

## Runs 5 to 7, from the recorded output

The notebooks stop at run D. `capture.sh` performs three more runs before its teardown, and their
output is in `capture/31` through `capture/42`.

Fixing one sink is not fixing the pipeline. The first repair changed only `truncateTable` on the
BigQuery sink, as `31-idempotent-diff.txt` shows. That version failed at **563 seconds**
(`33-run5-wait.txt`) and again at **400 seconds** (`35-run6-wait.txt`), with the same
`FileAlreadyExistsException` on the same sink. The table stayed at 20,001 rows because neither run
completed. The published `pipelines/03-idempotent.json` carries both halves of the fix.

**A schema change fails loudly.** `04-drift.json` removes the `set-type :amount double` directive,
so `amount` reaches the sink as a string while the BigQuery column is `FLOAT`. The run failed at
**361 seconds**, faster than any successful run, because the sink validates before it writes:

```
Stage 'SalesValidated' encountered : ValidationException:
Field 'amount' of type 'string' is incompatible with column 'amount'
of type 'double' in BigQuery table 'dsba6190_sales_75439.sales_validated'.
```

This is the same class of defect as step 9, a column whose type no longer matches. In step 9 the
pipeline succeeded and discarded rows. Here it failed and named the field, both types and the table.
The table still held 20,001 rows afterwards (`42-count-after-failure.txt`). A pipeline that halts
leaves the warehouse in the state it was in.

---

## Teardown

Tear down the same day. The instance bills $1.80 per instance-hour until it is deleted, and Data
Fusion offers no stopped state.

```sh
gcloud beta data-fusion instances delete "${INSTANCE:?}" \
  --project "${PROJECT:?}" --location us-central1 --quiet
gcloud beta data-fusion instances list --project "$PROJECT" --location us-central1
gcloud dataproc clusters list --project "$PROJECT" --region us-central1
gcloud storage rm -r "gs://${BUCKET:?}"
bq --project_id="${PROJECT:?}" rm -r -f -d "${DATASET:?}"
gcloud storage ls --project "$PROJECT"
gcloud storage buckets list --project "$PROJECT" \
  --filter="labels.cdf_instance=$INSTANCE" --format="value(name)"
bq --project_id="$PROJECT" ls
```

Every name is written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong
thing. Both `list` commands must answer `Listed 0 items.` A run stopped partway can leave a Dataproc
cluster behind, and its three nodes bill for as long as they exist.

The first run that builds a cluster also creates two Dataproc buckets,
`dataproc-staging-us-central1-<PROJECT_NUMBER>-<hash>` and
`dataproc-temp-us-central1-<PROJECT_NUMBER>-<hash>`. Neither the cluster deletion nor the instance
deletion removes them. Delete them with `gcloud storage rm -r` once no other Dataproc or Data Fusion
work in your project uses them. Data Fusion can also leave a bucket named `df-<digits>-<hash>` with
the label `cdf_instance=<INSTANCE>`. On the recorded run it was removed with the instance, and the
`buckets list` command above confirms it.

Four enabled APIs and the IAM grants remain after teardown. They cost nothing. The next morning,
open Billing, Reports, filter to your project and group by service. Cloud Data Fusion should show
zero against an unused allowance, or about $1.80 per instance-hour otherwise. Compute Engine and
Dataproc should show a few cents, and Cloud Storage and BigQuery less than a cent. This report is
the only evidence that the instance is gone rather than reported gone.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `Invalid choice: 'data-fusion'` | The command group is beta only. Run `gcloud components install beta` and use `gcloud beta data-fusion` |
| `create` ends after three seconds with `ERROR_CODE 10` and `Failed to perform tenant project creation` | The tenant-project build aborted. Re-issue the identical `create`. It is not a permissions or quota problem |
| `describe` returns `NOT_FOUND` while a create is in flight | The instance does not exist until its tenant project does. Read `gcloud beta data-fusion operations list`, which shows the create with no `END_TIME` while it is healthy |
| `artifacts` returns nothing | The instance is `RUNNING` but its API is still warming. Wait two minutes |
| A run fails about five seconds in, at `PROVISION`, listing missing `storage.objects.*` permissions | The cluster's service account lacks the Cloud Data Fusion API Service Agent role, and Editor does not substitute for it. Run `gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com --role roles/datafusion.serviceAgent --condition=None` |
| A run fails about five seconds in, at `PROVISION`, with `User not authorized to act as service account` | The Data Fusion service agent may not act as the cluster's service account. Run `gcloud iam service-accounts add-iam-policy-binding <PROJECT_NUMBER>-compute@developer.gserviceaccount.com --member serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-datafusion.iam.gserviceaccount.com --role roles/iam.serviceAccountUser` |
| A run goes from `PENDING` to `FAILED` in about two minutes, and the log says a zone `does not have enough resources available` | Compute Engine capacity ran short in the zone Dataproc chose. Pin a zone with `curl -X PUT -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" -d '{"system.profile.properties.zone":"us-central1-b"}' "$ENDPOINT/v3/namespaces/default/preferences"`, then re-run. Try `-a` or `-c` if `-b` is also short |
| A run fails for no stated reason on its first attempt | Data Fusion pipelines can fail spuriously. Re-run once. A second failure points to a missing grant |
| A run is still `STARTING` after twelve minutes | Dataproc is slow or short of capacity. Stop the run, confirm no cluster remains, and read the step from `capture/` |
| The Studio shows an empty namespace after sign-in | The browser is signed in as a different account. Open the Studio in the profile that matches `gcloud config get-value account` |
| Wrangler's recipe panel is empty after the clicks | The workspace lost its connection. Compare with `capture/06-wrangler-recipe.txt`, or import `pipelines/01-baseline.json` |
| The quarantine sink writes nothing | The error port connects to the wrong node, or `on-error` is still `skip-error`. Check both in the deployed pipeline's JSON |
| `bq` reports that the table does not exist | Step 10 dropped it, and run C has not finished. Wait for the run |
| A Studio node is not where step 3 or step 10 describes it | Import the matching JSON from `pipelines/` after substituting `PROJECT_ID`, `BUCKET_NAME` and `DATASET_NAME` |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-sample.py` | Generates the seeded clean extract, 20,000 rows and 1,131,128 bytes, and the malformed one with three more rows |
| `pipelines/make-pipelines.py` | Writes `01-baseline`, `02-quarantine`, `03-idempotent` and `04-drift`, pinned to the instance's plugin versions |
| `pipelines/0*.json` | The four definitions with placeholder identifiers, for import into the Studio |
| `cdap.py` | The CDAP REST client for deploy, start, wait, runs, logs, stages, lineage and delete |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and the real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
