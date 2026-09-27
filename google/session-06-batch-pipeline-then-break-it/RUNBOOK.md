# Session 6 live demo · runbook

A batch pipeline, then break it. One hour, twelve steps, 1:30 to 2:30 in the revised session plan.

Rehearsed end to end on 10 September 2026 against project `YOUR_PROJECT_ID`, Cloud Data Fusion
6.11.1 Basic edition, Google Cloud SDK 584.0.0, `google-cloud` plugins 0.24.1, `wrangler-transform`
4.11.1, `core-plugins` 2.13.1. Every command below was run. Every expected output below is real.

No Terraform is used in this demonstration. The pipeline is the artifact, and a Data Fusion pipeline
is JSON rather than HCL.

**Do not run `capture.sh` in class.** It is the headless recorder. It deletes the Data Fusion
instance through an exit trap, and the instance takes about sixteen minutes to rebuild.
`live-setup.sh` is its opposite: it provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you want to reproduce it on your own
> Google Cloud account, it costs approximately **$4**, which Google's $300 free credit for a
> new account covers many times over. Opening that account requires a credit card at signup, though
> Google does not charge it. That is your choice and no part of this course requires it.
> **Destroy what you create.** The teardown step is the last step for a reason.

The figure covers one Basic-edition Cloud Data Fusion instance for two to three hours, four
ephemeral Dataproc clusters of three `e2-custom-2-8192` nodes each, one Cloud Storage bucket holding
about 2 MB, and one BigQuery dataset. The capture run measured **1.22 instance-hours** for seven
pipeline runs; an in-class evening from T minus 60 to teardown is about 2.5.
**The instance is the whole number.** Basic edition bills $1.80 per
instance-hour and the first 120 instance-hours each month are free per billing account, so the same
usage is $0 on an account whose allowance is unconsumed and about $4 on one whose allowance is gone.
The clusters add roughly $0.04 per run and the storage and queries are under a cent. The figure is
an
estimate from list pricing and is not yet verified against the Google Cloud pricing calculator;
[`../../../docs/DEMO-RUNBOOKS-PLAN.md`](../../../docs/DEMO-RUNBOOKS-PLAN.md) section 6 records that
verification as a prerequisite for the student version of this document. It matches the Session 6
row in [`../../../docs/DEMO-DEVELOPMENT-PLAN.md`](../../../docs/DEMO-DEVELOPMENT-PLAN.md) section 7,
which is the authoritative estimate. Keep the two in agreement.

**The overnight number is the one to say out loud.** A Basic-edition instance left running costs
$25.20 for one night and $1,296 for a month. That is more than every other demonstration in this
course combined, and step 12 exists because of it.

---

## The scenario · Crown Street Markets

The hour is taught as one company's work. **Crown Street Markets** is fictional: a grocery chain with
40 stores across Mecklenburg County, headquartered in Charlotte. Every night each store's register
system drops a point-of-sale extract into Cloud Storage, and a three-person analytics team turns it
into the validated sales table store managers read at 7 a.m. Tonight's file is one business day:
20,000 transactions from stores `CLT-001` to `CLT-040`. A6's chain has 1,200 stores; Crown Street is
the pilot, and the pilot is where the defects surface.

| Step | What it is in the scenario |
|---|---|
| 1 to 5 | Building the pipeline that produces the store managers' morning table |
| 6 | The control numbers: one sales day across forty stores |
| 7 and 8 | A register software update sends three rows it should not have |
| 9 | The morning report shows the day twice, and two transactions are gone without a trace |
| 10 and 11 | Finance can reconcile the day, and the quarantined rows name their stores and reasons |
| 12 | The 3 a.m. rerun that fails for a reason unrelated to the data |

Introduce the company on the scenario slide that precedes the run sheet, in about two minutes.

---

## How the hour fits the session clock

The session plan carried this demonstration at fifteen minutes inside 1:10 to 1:50. It is now an
hour, and [`../../lecture-06-ingestion-integration.md`](../../lecture-06-ingestion-integration.md)
carries the matching timing table.

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Getting data in | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Choosing a tool, and scheduling it | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Guided lab · Lab 6, supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

This is the clock proposed in `DEMO-DEVELOPMENT-PLAN.md` section 3, adopted without change. Concept
Block 1 loses five minutes. Concept Block 2 was forty minutes with a fifteen-minute demonstration
inside it and is now twenty-five minutes of concept with the demonstration lifted out.

**The guided lab is a supervised start rather than a completion window, and this week that is not a
compromise.** Lab 6 pairs two activities whose provisioning alone consumes twenty-five to
forty-five minutes, and the lecture already tells students the labs are not expected to finish in
class. Twenty-five minutes buys the first action of each, which is the action that has to start
early: create the Data Fusion instance, then create the Airflow environment, then read while both
build. Say that at 2:30 in those words.

---

## The one thing this demonstration does differently

**A pipeline run takes seven and a half to nine and a half minutes, and most of that is not yours to
fill with silence.** The three runs that succeeded measured **454, 533 and 571 seconds**, and
`capture/43-all-runs.txt` lists all seven. On the run in `capture/09-run1-wait.txt` the split was
189
seconds queued, 110 seconds building the Dataproc cluster, and 156 seconds of Spark. On the next it
was 251, 141 and 189. **The variation sits almost entirely in the queue and the cluster build rather
than in the work**, so plan against the slow end and treat anything under eight minutes as luck.
Runs that fail come back sooner, between 361 and 563 seconds, because a sink that refuses validates
before it writes.

Every other demonstration in this course runs a command and reads the answer. This one starts a run
and then teaches for eight to nine minutes while it works. **The steps below are therefore written
as pairs: a
start, then the material that covers it, then the reading of the result.** Do not stand and watch
the
progress bar. The run is the timer, not the content.

Four runs fit in the hour. Six do not. That is the arithmetic that shaped the step list.

---

## Before class

This is the longest pre-class sequence in the course and every part of it is waiting. The whole
schedule, so it can be read at a glance:

| Clock | Do | Takes |
|---|---|---|
| T minus 60 | `./live-setup.sh YOUR_PROJECT_ID` | about 16 minutes, most of it the instance |
| T minus 44 | `source ~/dsba6190-live-demo-06/env.sh`, check the four plugin artifacts | 1 minute |
| T minus 42 | Start the smoke run and let it finish | 8 to 10 minutes |
| T minus 30 | Delete the smoke app and its table, confirm no cluster survives | 2 minutes |
| T minus 25 | Set up the room. Studio, Dataproc tab, terminal, deck | 5 minutes |

**Nothing here can be compressed.** Every line is a wait on a service, and the two that matter most,
the instance build and the smoke run, are the two that cannot be shortened at all.

### T minus 60 minutes

```sh
cd "lectures/demos/session-06-batch-pipeline-then-break-it"
./live-setup.sh YOUR_PROJECT_ID
```

**Sixty minutes, not thirty.** The instance is the only resource in this course that cannot be
created inside the hour it is needed. Two builds were measured on 10 September: **16 minutes
46 seconds** and **15 minutes 20 seconds** from `create` to `RUNNING`. On the first, two create
attempts aborted after three seconds each and had to be re-issued before the third worked. Sixty
minutes is that build plus two failed starts plus the margin to notice.

Google's documentation says about ten minutes. This course used to say fifteen to twenty-five. Both
measurements land near sixteen, and the number to plan against is the measured one.

**This script provisions.** It creates the Data Fusion instance and blocks until it reports
`RUNNING`, makes three IAM grants, creates the bucket and the BigQuery dataset, generates the two
point-of-sale extracts, uploads the clean one, and writes the four pipeline definitions against the
plugin versions the instance actually carries. It deploys nothing and runs nothing. The hour does
that.

It prints the working directory, the name suffix, every resource name, the Studio URL, and the
teardown. Note the suffix. The default working directory is `~/dsba6190-live-demo-06`.

```sh
source ~/dsba6190-live-demo-06/env.sh
```

That puts `$PROJECT`, `$BUCKET`, `$DATASET`, `$FQ` and `$ENDPOINT` into the shell you teach from, so
no command below needs a name typed by hand.

### T minus 44 minutes, verify

```sh
python3 cdap.py artifacts --endpoint "$ENDPOINT"
```

Expect exactly four rows:

```
cdap-data-pipeline       6.11.1       SYSTEM
core-plugins             2.13.1       SYSTEM
google-cloud             0.24.1       SYSTEM
wrangler-transform       4.11.1       SYSTEM
```

An empty answer means the instance reports `RUNNING` but its API is not serving yet. Wait two
minutes
and try again. Anything else means fix it now rather than at 1:30.

**Then run one pipeline and throw it away.** This is the only demonstration in the course that asks
for a smoke test, and the reason is that both of its IAM failure modes fail late. A missing grant
does not fail at deploy. It fails about five seconds into a run, forty minutes from now, in front of
the room, and it looks like a broken pipeline rather than a permissions problem.

```sh
python3 cdap.py deploy --endpoint "$ENDPOINT" --app smoke \
  --file ~/dsba6190-live-demo-06/pipelines/01-baseline.json
SMOKE=$(python3 cdap.py start --endpoint "$ENDPOINT" --app smoke)
python3 cdap.py wait --endpoint "$ENDPOINT" --app smoke --run "$SMOKE"
```

**Let it finish.** It takes seven and a half to nine and a half minutes, which is why it starts at
T minus 42 and not at T minus 5. Stopping it early is the tempting move and the wrong one: a run
killed between `PENDING`
and `RUNNING` can leave its Dataproc cluster behind, and a cluster nobody is watching is exactly the
charge this session spends an hour warning about.

What matters is the transition. A run that reaches `STARTING` has already cleared every permission
the hour depends on, so once you see `STARTING` the grants are proven and the rest is confirmation.
A run that dies in `PENDING` after about five seconds has not, and the two IAM rows in the table
below name which grant is missing.

Then remove the app, the table it wrote, and the quarantine prefix if it made one:

```sh
python3 cdap.py delete --endpoint "$ENDPOINT" --app smoke
bq --project_id="$PROJECT" rm -f -t "$DATASET.sales_validated"
gcloud dataproc clusters list --project "$PROJECT" --region us-central1
```

**The last command must answer `Listed 0 items.`** If it does not, delete what it lists before class
starts. The smoke test costs about four cents and thirty seconds of attention, and it buys the one
thing this demonstration cannot recover from: discovering a missing grant at 1:46 with forty-five
minutes of material behind it.

### Common causes, in the order they occur

| Symptom | Cause | Fix |
|---|---|---|
| `Invalid choice: 'data-fusion'` | The command is beta-only. There is no GA `gcloud data-fusion` | `gcloud components install beta`, then use `gcloud beta data-fusion` |
| `create` returns an operation, and the operation ends three seconds later with `ERROR_CODE 10` and `Failed to perform tenant project creation` | Data Fusion builds a tenant project behind the instance and that build can abort. It is not permissions and not quota | Re-issue the identical `create`. It aborted twice on 10 September and built on the third attempt |
| `describe` returns `NOT_FOUND` while `create` is in flight | The instance does not materialise until the tenant project exists | Read `gcloud beta data-fusion operations list` instead, which shows the create with no `END_TIME` while it is healthy |
| A run fails after about five seconds at `PROVISION`, listing missing `storage.objects.*` permissions on the default compute service account | The cluster's identity does not hold **Cloud Data Fusion API Service Agent**. This is Lab 6's second IAM grant, and Editor on the same account does not substitute for it | `gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com --role roles/datafusion.serviceAgent --condition=None` |
| A run fails after about five seconds at `PROVISION` with `User not authorized to act as service account` | The Data Fusion service agent may not act as the cluster's identity. Lab 6 does not mention this grant | `gcloud iam service-accounts add-iam-policy-binding <PROJECT_NUMBER>-compute@developer.gserviceaccount.com --member serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-datafusion.iam.gserviceaccount.com --role roles/iam.serviceAccountUser` |
| The Studio asks to sign in and then shows an empty namespace | The browser is signed in as a different Google account than the one holding access to the instance | Open the Studio in the profile that matches `gcloud config get-value account` |
| A run fails for no stated reason on the first attempt | Google's own Lab 6 note says a Data Fusion pipeline can fail spuriously and the remedy is to re-run | Re-run it once. Treat one failure as noise and a second as a missing grant |
| `artifacts` returns nothing | The instance is `RUNNING` but the API is still warming | Wait two minutes |
| A run goes `PENDING` to `FAILED` in about two minutes, and the log says a zone `does not have enough resources available` | A Compute Engine capacity shortage in the zone Dataproc chose automatically. Not permissions, not the pipeline. Seen on 24 September 2026 in `us-central1-f` | Pin the zone for every run: `curl -X PUT -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" -d '{"system.profile.properties.zone":"us-central1-b"}' "$ENDPOINT/v3/namespaces/default/preferences"`, then re-run. Try `-a` or `-c` if `-b` is also short |

### Set up the room

- Browser on the Data Fusion Studio, signed in, with the Wrangler workspace open. The Studio URL is
  in the `live-setup.sh` output and in `$CONSOLE`.
- A second browser tab on the Cloud Console, Dataproc, Clusters, in the demo project. Step 4 watches
  a cluster appear there and step 12 confirms it is gone.
- Terminal at a size the back row can read, with `env.sh` sourced. Row counts are the teaching
  material and they arrive in the terminal.
- A third tab on the BigQuery console for the table preview, which reads better from the back row
  than a `bq` result grid does.
- Deck on slide 37, the Live Demonstration divider, with the Crown Street Markets scenario on 38,
  the run sheet on 39 and 40, and the twelve capture slides that follow at 41 to 52.
- The Week 5 zone diagram still on the board. Step 3 maps three pipeline nodes onto it.

**Network contingency.** If the room has no working connection, present from the deck. Slides 41 to
52 carry one capture slide per step, trimmed to the type floor and drawn from the same outputs, and
the full text of every command is in `capture/`. Every file in it is real output from the
10 September rehearsal, one file per command, numbered in the order below. Say plainly that the run
is recorded rather than live. The repository standard is that a capture is labelled as one.

**This demonstration has a second contingency the others do not need.** If a run fails twice for a
reason the failure table does not name, do not debug it in front of the room. Move to `capture/`,
say the run is recorded, and keep the hour's argument intact. The argument does not depend on the
run succeeding tonight. It depends on the row counts, and the row counts are recorded.

---

## The sequence

Every terminal command is run from the shell that sourced `env.sh`. Every Studio action is performed
in the browser tab already signed in. Substitute the suffix `live-setup.sh` printed wherever
`<SUFFIX>` appears; the captured outputs below carry `75439`, the rehearsal's suffix.

**Four pipeline runs fit in this hour.** They are started at steps 4, 7, 10 and 12, and the step
that
follows each start is the material that covers it. Each step below names the run that is in flight
while it is taught. Do not reorder them: each run leaves the table the next step reads.

| # | Step | Minutes | Run in flight |
|---|---|---|---|
| 1 | The instance, the edition, and the meter that is already running | 4 | none |
| 2 | The Wrangler recipe is a directive list, and a directive list is code | 6 | none |
| 3 | Three nodes, two edges, and the Week 5 zones on the board | 5 | none |
| 4 | Deploy, run, and watch the cluster the instance-hour buys | 5 | **A starts** |
| 5 | What one run provisions, and what it costs | 5 | A |
| 6 | The control number | 3 | none |
| 7 | The malformed day arrives, on the same pipeline | 3 | **B starts** |
| 8 | Retry, quarantine, halt, while the run works | 7 | B |
| 9 | One query, two defects | 5 | none |
| 10 | The fix is two properties, and one of them is not enough | 5 | **C starts** |
| 11 | Field-level lineage, then the count that reconciles | 7 | C |
| 12 | Change nothing, run it again, and delete the instance | 10 | **D** |
| | **Total** | **60** | |

### Step 1 · The instance, the edition, and the meter · slide 34 · 4 minutes

Start in the Cloud Console, on the Data Fusion instance list, not in the Studio.

```sh
gcloud beta data-fusion instances describe "$INSTANCE" \
  --project "$PROJECT" --location us-central1 \
  --format="yaml(name,state,type,version,apiEndpoint)"
```

Expect `state: RUNNING` and `type: BASIC`.

**What to notice.** Three sentences, said in this order, and then move on.

The instance was created at a time you name out loud, and it has been billing since that moment
whether or not a pipeline ever runs. Basic edition is $1.80 per instance-hour. Nothing tonight will
consume more than two of those hours, and the first 120 each month are free on this billing account,
so tonight is free. Say the overnight number anyway: $25.20 for one night, $1,296 for a month.

Then say what it cost in time. **The instance took about sixteen minutes to build, measured twice at
15:20 and 16:46, and on one of those builds the first two create attempts failed after three seconds
each.** That is why it was provisioned an hour ago rather than now, and it is the first honest
answer to the cost question A6 asks: Data Fusion's price is not the per-run price, it is the
standing
price of having the thing available.

This is the only slide where cost is the subject rather than a footnote. **Cost is a first-class
topic in this session** because A6 grades it.

### Step 2 · The recipe is a directive list, and a directive list is code · slide 25 · 6 minutes

In the Studio, open **Wrangler**, connect to Cloud Storage, and load
`gs://dsba6190-pos-<SUFFIX>/raw/pos/pos-2026-09-24.csv`. Then build the recipe by clicking, because
clicking is what students will do:

1. Parse the body as CSV, first row as header.
2. Drop `body` and `offset`.
3. Rename the six columns.
4. Set `qty` to integer and `amount` to double.
5. Parse `txn_ts` as a datetime with the pattern `yyyy-MM-dd HH:mm:ss`, then convert it to a
   timestamp.

Now open the recipe panel on the right. It reads:

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

**What to notice.** Thirteen clicks produced thirteen lines of code, and the lines are the artifact
rather than the clicks. Say that in those words. A recipe can be read in a pull request, diffed
between two versions, and pasted into a colleague's workspace, and none of that is true of the
clicking. This is the answer to the objection that a visual tool is not real engineering.

Then name the limit honestly, because A6 grades portability. **This recipe is CDAP's directive
language and it runs nowhere except Data Fusion.** The Airflow DAG in tonight's lab is plain
open-source Python and runs on Amazon MWAA, on Astronomer, and on a laptop. That contrast is a
legitimate A6 argument and this is the moment to hand it to the room.

Ask which two directives are doing the dangerous work. The answer is the two `set-type` lines and
the
`parse-as-datetime` line, because those are the three that can fail on a row, and step 8 is about
what a failure means.

### Step 3 · Three nodes, two edges, and the zones on the board · slide 19 · 5 minutes

Take the recipe into a pipeline. On the canvas: a **GCS** source, the **Wrangler** transform, a
**BigQuery** sink. Two edges. Then read it back as the document it is:

```sh
python3 - <<'PY'
import json, pathlib
d = pathlib.Path.home() / "dsba6190-live-demo-06" / "pipelines"
p = json.loads((d / "01-baseline.json").read_text())
for s in p["config"]["stages"]:
    print(f'  {s["name"]:<22} {s["plugin"]["type"]:<16} {s["plugin"]["name"]}')
print()
for e in p["config"]["connections"]:
    print(f'  {e["from"]:<22} -> {e["to"]}')
PY
```

Expect:

```
  PointOfSaleRaw         batchsource      GCSFile
  Wrangler               transform        Wrangler
  SalesValidated         batchsink        BigQueryTable

  PointOfSaleRaw         -> Wrangler
  Wrangler               -> SalesValidated
```

**What to notice.** Point at the Week 5 zone diagram still on the board and map the three nodes onto
it out loud. The source reads `raw/`, which Week 5 established as immutable. The sink writes a
validated table. Nothing writes back into `raw/`, and that is the whole reason last week insisted on
immutability: tonight's pipeline is going to be wrong, and being able to re-run it against unchanged
source is the property that makes being wrong survivable.

Then name the shape. Three nodes and two edges is a directed acyclic graph, which is the same
vocabulary the Airflow half of tonight's lab uses for a different thing. **A pipeline's DAG is
stages of one data movement. An orchestrator's DAG is many movements in order.** Students conflate
these constantly and this is the cheapest moment to separate them.

### Step 4 · Deploy, run, and watch what the instance-hour buys · slide 34 · 5 minutes

```sh
python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-01-baseline \
  --file ~/dsba6190-live-demo-06/pipelines/01-baseline.json
python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline
```

Expect the deploy to report three stages and two edges, and the start to print a run id. **Start the
run before you explain anything.** It takes eight to nine minutes and the next two steps are what
covers
it.

Now switch to the Dataproc tab in the Console and refresh it until a cluster appears, which takes
about ninety seconds:

```sh
gcloud dataproc clusters list --project "$PROJECT" --region us-central1 \
  --format="table(clusterName,status.state,config.masterConfig.machineTypeUri.basename(),
                  config.workerConfig.numInstances,
                  config.workerConfig.machineTypeUri.basename())"
```

Expect one cluster named for the pipeline and the run id:

```
NAME                                    STATUS    MACHINE_TYPE      WORKERS  WORKER_TYPE
cdap-pos-01-ba-<RUN_ID>                 CREATING  e2-custom-2-8192  2        e2-custom-2-8192
```

**What to notice.** Nobody asked for that cluster and nobody will delete it. Data Fusion created a
three-node Dataproc cluster to run one pipeline over a one-megabyte file, and it will destroy the
cluster when the run ends. **That is the second line on the invoice**, and the lab's Task 6 note
describes it in one sentence that most students read past.

Say the arithmetic out loud, because it is the honest version of the cost model: the instance-hour
buys the Studio, the connectors, the lineage and the scheduler. The cluster is what actually reads
the bytes, and it is billed separately, per run, for as long as the run takes.

### Step 5 · What one run provisions, and what it costs · slide 34 · 5 minutes

The run is still working. Use the time, and do not fill it by refreshing the page.

Walk the four phases the run passes through, which the terminal will print as it goes:

| Phase | On the rehearsal | What is happening |
|---|---|---|
| `PENDING` | 0 to 189 seconds | The request is queued against the instance |
| `STARTING` | 189 to 299 seconds | Dataproc is building the cluster |
| `RUNNING` | 299 to 455 seconds | Spark is reading, transforming and writing |
| `COMPLETED` | 455 seconds | The cluster is deleted |

**What to notice.** Most of the run is not the work. Two and a half minutes of Spark over 20,000
rows,
and five minutes of waiting for somewhere to run it. Ask the room what that implies about a pipeline
scheduled every five minutes, and let the answer arrive: this architecture is built for batch and it
is the wrong shape for anything that needs to be fresh. That is Week 11's subject and this is the
evidence for it.

Then price it. Three `e2-custom-2-8192` nodes are about $0.20 an hour together, the Dataproc
surcharge over six vCPU adds about $0.06 an hour, and a ten-minute run therefore costs about
**$0.04**.
Set that beside $1.80 per instance-hour and the shape of Data Fusion's economics is visible in one
comparison: **the runs are nearly free and the availability is not.** A team running two hundred
pipelines a day amortises the instance. A team running one pipeline a week is paying $1,296 a month
for a Studio they open on Tuesdays. **That trade is a defensible A6 answer in either direction**,
and
the room now has the numbers to argue it.

### Step 6 · The control number · slide 18 · 3 minutes

The run reaches `COMPLETED`. Read the result.

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded, ROUND(SUM(amount), 2) AS total_amount,
          COUNTIF(txn_ts IS NULL) AS null_ts
   FROM \`$FQ\`"
```

Expect:

```
+-------------+--------------+---------+
| rows_loaded | total_amount | null_ts |
+-------------+--------------+---------+
|       20000 |   2422034.45 |       0 |
+-------------+--------------+---------+
```

**What to notice.** Write **20,000** and **2,422,034.45** on the board and leave them there. They
are
the control numbers for steps 9, 11 and 12, and the entire second half of this hour is the room
watching them fail to hold.

Say what a clean run looks like so the unclean one is recognisable: every row that left the file
arrived in the table, no timestamp is null, and the total is a number a finance team could
reconcile against a different system. That last property is the one that matters, and it is the one
that breaks first.

### Step 7 · The malformed day arrives · slide 13 · 3 minutes

Overnight the source system sent a file with three rows in it that it should not have sent. Put it
in place of the clean one, under the same object key, because that is what a real ingest does.

```sh
gcloud storage cp ~/dsba6190-live-demo-06/sample/pos-2026-09-24-dirty.csv \
  "gs://dsba6190-pos-<SUFFIX>/raw/pos/pos-2026-09-24.csv"

tail -3 ~/dsba6190-live-demo-06/sample/pos-2026-09-24-dirty.csv
```

```
T-0900001,CLT-007,not-a-date,SKU-01042,2,18.50
T-0900002,CLT-013,2026-09-24 11:04:22,SKU-01077,1,N/A
T-0900003,CLT-022,2026-09-24 15:41:09,SKU-01003,-4,62.00
```

Read the three rows aloud and ask what each one breaks. Take answers for the first two and do not
give the answer for the third.

Then start the run. **Nothing about the pipeline has changed.**

```sh
python3 cdap.py start --endpoint "$ENDPOINT" --app pos-01-baseline
```

**What to notice.** Say plainly that you edited no pipeline, no schema and no recipe. The only thing
that changed is a file, and the file changed the way real source data changes: quietly, under the
same name, between two runs nobody was watching.

### Step 8 · Retry, quarantine, halt · slide 14 · 7 minutes

Ten minutes of run, and this is the concept block Concept Block 1 compressed to pay for.

Draw the three failure paths branching from a single ingest step, which the board checklist already
calls for.

| Path | When | What it does |
|---|---|---|
| **Retry** | Transient. Network, throttling, a busy endpoint | Back off and try again. Safe only if the task is idempotent |
| **Quarantine** | Bad data. One row is wrong and the rest are fine | Route the row to a dead-letter path and keep going |
| **Halt** | Systemic. Schema violation, auth failure, the source is gone | Stop and page somebody |

Then name the fourth path, which is not on the list because nobody chooses it deliberately.

**Silent coercion.** A numeric column arrives as a string, something casts it to null, the row
loads,
and the dashboard is confidently and quietly wrong. It is the worst of the four because it is the
only one that produces no signal at all. There is no alert, no failed run, and no red node on the
canvas. There is a number in a meeting that nobody can reconcile, three weeks later.

Ask the room which of the four Wrangler is currently configured to do. The answer is on the pipeline
and none of them have seen it: the transform's `on-error` property is `skip-error`, which is the
default, and the default is closest to silent coercion.

**What to notice.** Set up the next step without spoiling it. Tell the room the run is loading a
file
with three known-bad rows, that they have been told what the pipeline does with bad rows, and
that in four minutes they should predict the row count before you read it. Take a show of hands on
20,000, 20,001, 20,003 and "it fails". Write the vote on the board.

Almost nobody votes for the number that appears.

### Step 9 · One query, two defects · slide 12 and 13 · 5 minutes

The run reaches `COMPLETED`. It did not fail. Read the same query as step 6.

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"
```

```
+-------------+
| rows_loaded |
+-------------+
|       40001 |
+-------------+
```

Let that sit. Then read what the transform itself recorded, which is the number the Studio prints on
the Wrangler node:

```sh
python3 cdap.py stages --endpoint "$ENDPOINT" --app pos-01-baseline \
  --run "$RUN" --stage Wrangler
```

```
Wrangler               records in       20004
Wrangler               records out      20001
```

Then ask where the three bad rows went, and look for them by name.

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT txn_id, txn_ts, qty, amount FROM \`$FQ\`
   WHERE txn_id IN ('T-0900001','T-0900002','T-0900003') ORDER BY txn_id"
```

```
+-----------+---------------------+-----+--------+
|  txn_id   |       txn_ts        | qty | amount |
+-----------+---------------------+-----+--------+
| T-0900003 | 2026-09-24 15:41:09 |  -4 |   62.0 |
+-----------+---------------------+-----+--------+
```

**What to notice.** One query, two defects, and they are unrelated to each other. Take them in this
order and do not let the second one eat the first.

**The count is 40,001.** The pipeline ran twice against a table it appends to, so run A's 20,000
rows
are still there and run B added 20,001 more. Every transaction from the clean day is now in the
warehouse twice. The
pipeline is **not idempotent**, and the word arrives for the third time in this course after
Terraform in Week 3 and the raw zone in Week 5. Say that a retry policy on this pipeline would be a
machine for producing duplicates, and that tonight's lab sets `'retries': 1` on every task in its
DAG. Steps 10 and 12 fix this.

**Three records went into Wrangler and did not come out, and nobody was told.** The stage counts say
20,004 in and 20,001 out. One of the three is benign and known: the header line, consumed by
`parse-as-csv` exactly as it was in step 6. The other two are `not-a-date`, which failed the
datetime
parse, and `N/A`, which failed the cast to double. `skip-error` discarded both without a warning, a
log line, or a failed run. **The pipeline reported success.** That is the silent coercion from step
8,
performed rather than described, and the fact that a benign loss and a catastrophic one look
identical in these counters is the reason it is dangerous. Ask what the
finance team's reconciliation looks like when two transactions are missing from a day and nothing
anywhere says so.

**And the third row loaded.** `T-0900003` has a quantity of **-4**, which is perfectly well typed
and
plainly wrong. No schema catches it, no cast fails on it, and no error path exists for it. **A
type system is not a quality gate.** Row counts and null checks would not have caught this either;
only a rule that knows a quantity cannot be negative catches it, and writing that rule is a decision
somebody has to make on purpose. That distinction is worth a slow minute, because A6's scenario is
retail point-of-sale data and a negative quantity is a return, a correction, or a fraud, and knowing
which one is a business question rather than an engineering one.

### Step 10 · The fix is two properties · slide 14 · 5 minutes

Two changes, in two different places, fixing two different defects. Show them as a diff before
touching the canvas.

```sh
python3 - <<'PY'
import json, pathlib
d = pathlib.Path.home() / "dsba6190-live-demo-06" / "pipelines"
a = json.loads((d / "01-baseline.json").read_text())["config"]
b = json.loads((d / "02-quarantine.json").read_text())["config"]
an = {s["name"] for s in a["stages"]}
for s in b["stages"]:
    if s["name"] not in an:
        print(f'  + {s["name"]:<22} {s["plugin"]["type"]:<16} {s["plugin"]["name"]}')
ae = {(e["from"], e["to"]) for e in a["connections"]}
for e in b["connections"]:
    if (e["from"], e["to"]) not in ae:
        print(f'  + {e["from"]:<22} -> {e["to"]}')
PY
```

```
  + QuarantineCollector    errortransform   ErrorCollector
  + QuarantineSink         batchsink        GCS
  + Wrangler               -> QuarantineCollector
  + QuarantineCollector    -> QuarantineSink
```

In the Studio, make the same two changes on the canvas so the room sees the branch drawn: set
Wrangler's error handling to **send to error port**, drag an **Error Collector** onto the canvas,
connect Wrangler's error port to it, and connect that to a **GCS** sink writing to
`gs://dsba6190-pos-<SUFFIX>/quarantine/pos`. Deploy and run.

```sh
bq --project_id="$PROJECT" rm -f -t "$DATASET.sales_validated"
python3 cdap.py deploy --endpoint "$ENDPOINT" --app pos-02-quarantine \
  --file ~/dsba6190-live-demo-06/pipelines/02-quarantine.json
python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine
```

**What to notice.** The table is dropped first, deliberately and in front of the room, and that is
itself the point. **Dropping the table by hand is not a fix, it is a workaround**, and it is what
every team does the first time this happens at 3 a.m. The real fix arrives at step 12, and this step
deliberately leaves it undone so the room can see that the quarantine branch and idempotency are two
separate problems with two separate solutions. Fixing one does not fix the other.

Say what the error port is. Wrangler already knew those two rows were bad. It had the row, the
column, and the reason, and `skip-error` threw all three away. The branch does not detect anything
new; it stops discarding what was already detected.

### Step 11 · Field-level lineage, then the count that reconciles · slide 18 · 7 minutes

The run has eight minutes to go. Open the **Lineage** tab on the deployed pipeline, choose the
`amount` field, and walk it backwards from the BigQuery column to the CSV column it came from.

**What to notice.** The lecture's line is that lineage is the difference between an afternoon and a
fortnight. Make it concrete with tonight's own artifact. `amount` in the validated table came from
column six of a CSV in `raw/`, by way of a `set-type` directive that discarded every row it could
not
cast. **The discarding is visible in the lineage and invisible in the data**, and a person asked in
three weeks why the daily total is low has exactly one place to look that answers the question.

Then say what lineage is not. It records what the pipeline did, not whether it was right. It would
have shown the same clean graph for the run that dropped two rows and the run that loaded a negative
quantity. Lineage answers "where did this number come from" and never answers "is this number
correct".

When the run completes, read both halves of the reconciliation.

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded FROM \`$FQ\`"

gcloud storage cat "gs://dsba6190-pos-<SUFFIX>/quarantine/pos/**" | head -4
```

```
+-------------+
| rows_loaded |
+-------------+
|       20001 |
+-------------+
```

```
{"offset":1131128,
 "body":"T-0900001,CLT-007,not-a-date,SKU-01042,2,18.50",
 "errMsg":"Value not-a-date for column txn_ts is not in expected format
           yyyy-MM-dd HH:mm:ss (ecode: 2, directive: parse-as-datetime)",
 "errCode":2,"errStage":"Wrangler"}

{"offset":1131175,
 "body":"T-0900002,CLT-013,2026-09-24 11:04:22,SKU-01077,1,N/A",
 "errMsg":"Error encountered while executing 'set-type' :
           Column 'amount' cannot be converted to a 'double'.",
 "errCode":0,"errStage":"Wrangler"}
```

**What to notice.** 20,001 plus two quarantined is 20,003, which is exactly the number of rows in
the
file. **The count reconciles for the first time tonight.** That is the property a data quality gate
actually delivers: not that nothing goes wrong, but that when something does, the arithmetic still
closes and somebody can be told what was lost.

Read one quarantined record aloud, slowly, because it carries four things and every one of them
matters. **The original row, byte for byte.** **The byte offset in the source file**, so the record
can be found in `raw/` without guessing. **The stage that rejected it**, which is `Wrangler`. And
**the reason, naming the directive**: `parse-as-datetime` rejected `not-a-date` for not matching
`yyyy-MM-dd HH:mm:ss`, and `set-type` refused to make a double out of `N/A`.

Compare that with step 9, where the same two rows produced nothing at all. **The information existed
both times.** The difference is one property on one node, and the difference in what a person can do
about it three weeks later is total.

And point at the 1 in 20,001. The negative quantity is still there. **The branch fixed the rows the
pipeline knew were bad and did nothing for the row it never suspected**, which is the difference
between schema validation and a quality gate and is the last thing on the board before the payload.

### Step 12 · Change nothing, run it again, then delete it · slide 12 · 10 minutes

Start the run first, because the last ten minutes belong to it.

```sh
python3 cdap.py start --endpoint "$ENDPOINT" --app pos-02-quarantine
```

**Change nothing.** Same pipeline, same file, same everything. Ask the room what the count will be
when it finishes, and hold them to an answer. Nobody predicts what happens.

While it runs, put the two numbers from step 9 back on the board. Twenty thousand and one rows
loaded, forty thousand and one in the table after two runs of the pipeline without the branch. That
is the ordinary shape of a non-idempotent pipeline: it succeeds, and it quietly doubles the day.

Then the run finishes, and it does not double anything.

```
      0s  PENDING
    172s  STARTING
    282s  RUNNING
    392s  FAILED
```

```sh
bq --project_id="$PROJECT" --quiet query --use_legacy_sql=false --nouse_cache --format=pretty \
  "SELECT COUNT(*) AS rows_loaded, COUNT(DISTINCT txn_id) AS distinct_txn_id FROM \`$FQ\`"
```

```
+-------------+-----------------+
| rows_loaded | distinct_txn_id |
+-------------+-----------------+
|       20001 |           20001 |
+-------------+-----------------+
```

Read the log, because the reason is one line and it is the payload.

```sh
python3 cdap.py logs --endpoint "$ENDPOINT" --app pos-02-quarantine \
  --run "$RUN" --grep FileAlreadyExists --tail 1
```

```
Stage 'QuarantineSink' encountered :
org.apache.hadoop.mapred.FileAlreadyExistsException:
Output directory gs://dsba6190-pos-<SUFFIX>/quarantine/pos already exists
```

**This is the demo's payload, and it is not the one the room expects.** Say it in one sentence and
let it land. **The pipeline could not be run a second time at all.** Not because the data was wrong,
not because the schema changed, and not because anything about tonight was unusual. The error sink
wrote a directory on the first run, and a Hadoop output committer refuses to write into a directory
that already exists.

Then draw the three consequences out, in this order.

**Idempotency is not one property of a pipeline. It is a property of every sink in it.** The
BigQuery sink would have appended and doubled the day. The Cloud Storage sink refused to run at all.
Same pipeline, same second run, two different failures, and fixing one would not have revealed the
other. Ask which failure they would rather have at 3 a.m., and let them argue: the loud one costs a
night's sleep and the silent one costs a quarter's reporting.

**The quarantine branch that fixed step 9 introduced this.** The pipeline in step 4 had no error
sink
and could be re-run all night, wrongly. Adding the control that made the count reconcile is what
made
the pipeline un-runnable twice. **Every control has a cost and this one's arrived four minutes
later.**
That is the honest version of the design conversation A6 asks for.

**And the fix is the deterministic partition target from Concept Block 1.** Both halves:

```
SalesValidated   truncateTable  'false' -> 'true'
QuarantineSink   path  gs://.../quarantine/pos
                    -> gs://.../quarantine/pos/dt=${logicalStartTime(yyyy-MM-dd-HHmmss)}
```

The BigQuery sink replaces the day rather than adding to it. The error sink writes a new prefix per
run rather than one fixed directory. `pos-03-idempotent.json` in the working directory carries both,
and `pipelines/03-idempotent.json` in the repository carries them with placeholder identifiers so it
can be imported. **Name the fix. Do not run it.** There is no fifth run in this hour, and the room
should leave holding the defect rather than the repair.

Then connect it to tonight's lab in one move. The Airflow DAG students are about to run sets
`'retries': 1` on every task. Ask what that retry would have done here, and do not soften the
answer:
it would have re-run a task that cannot succeed twice, failed identically, and reported a failed DAG
at 3 a.m. for a pipeline whose data was never wrong. **A retry is only safe if the task is
idempotent**, and this is the fourth time that sentence has appeared in this course.

**Then delete the instance in front of the room.**

```sh
gcloud beta data-fusion instances delete "$INSTANCE" \
  --project "$PROJECT" --location us-central1 --quiet

gcloud beta data-fusion instances list --project "$PROJECT" --location us-central1
```

Expect `Listed 0 items.`

**End here.** Say the overnight number one more time, because it is the last thing worth carrying
out
of the room: an instance nobody deleted costs $25.20 by breakfast and $1,296 by the end of the
month,
and it costs that whether or not a single pipeline ever runs on it. **The most expensive mistake in
this entire course is not a wrong architecture. It is a resource nobody turned off.** Then move to
the lab at 2:30 and tell students to start the Data Fusion instance as their first action, because
they have now watched how long it takes.

---

## What the hour skips, and where the evidence is

The recorder runs seven pipelines. The hour runs four, and the four it runs are the recorder's runs
1, 2, 3 and 4. **Two arguments are therefore made from `capture/` rather than performed**, and the
runbook says so rather than pretending the hour is complete.

| Argument | Why the hour skips it | Capture |
|---|---|---|
| **Fixing one sink is not fixing the pipeline.** `truncateTable` alone leaves the error sink failing identically | Two more runs, and the hour ends on the defect rather than the repair | `31` through `36` |
| A schema change fails loudly, and loudly is better than quietly | A further run, and it has to build a cluster before it can fail | `37` through `42` |

**The first row is worth reading in the captures rather than summarising.** `31-idempotent-diff.txt`
shows the one property the first repair changed. `33-run5-wait.txt` shows that repair failing after
563 seconds with the same `FileAlreadyExistsException` on the same sink, and `35-run6-wait.txt`
shows
it failing again at 400 seconds. **The same defect twice, after a repair.** **A fix that addresses
the
defect you noticed and not the one you did not is the ordinary shape of a 3 a.m. repair**, and this
is the cheapest place in the course to watch it happen. The committed
`pipelines/03-idempotent.json` carries the corrected version, with both sinks made safe.

**Ending on the defect is deliberate, not a shortage of time.** Step 12 shows a pipeline that cannot
be run twice and names the two-part fix without running it. A room that watches the repair succeed
remembers the repair. A room that leaves with `FileAlreadyExistsException` on the board remembers
the
defect, and the defect is what A6 asks them to design against.

**The second row is the one to project if there is time in the lab slot.** It is the counterpart to
step 9: the same class of defect, a column whose type no longer matches, handled by refusing the
load
rather than by discarding rows. One directive was removed from the recipe, so `amount` reached the
sink as a string, and the sink refused it:

```
Stage 'SalesValidated' encountered : ValidationException:
Field 'amount' of type 'string' is incompatible with column 'amount'
of type 'double' in BigQuery table 'dsba6190_sales_75439.sales_validated'.
```

**Read that error beside step 9's silence.** Both are the same defect: a column whose type no longer
matches what the warehouse expects. In step 9 the pipeline succeeded and threw the rows away. Here
it
failed and named the field, the type it got, the type it wanted, and the table. The run took 361
seconds and failed faster than any successful run, because the sink validates before it writes.

And `capture/42-count-after-failure.txt` shows the table still holding 20,001 rows, which is the
point. **A pipeline that halts leaves the warehouse in the state it was in.** A pipeline that
coerces
silently does not.

---

## Teardown

Run this the same evening. Not tomorrow. **This is the most important section in this document.**
Session 5's teardown protected against a fraction of a cent. This one protects against $1,296 a
month, and it is the only demonstration in this course where forgetting costs more than every other
demonstration combined.

- [ ] **Destroy by the mechanism that created it.** There is no Terraform in this demonstration. The
      instance, the bucket and the dataset were created by `live-setup.sh` and are removed by the
      three commands it printed. A pipeline deleted in the Studio but left deployed is harmless; an
      instance deleted in the Studio is not possible, because the Studio cannot delete its own
      instance.
- [ ] **Compute.** No Dataproc cluster remains. Each run creates one and deletes it, but a run that
      was killed mid-flight can leave one behind, and three `e2-custom-2-8192` nodes bill for as long
      as they exist. Verify in the Console, not in the terminal:
      `gcloud dataproc clusters list --project YOUR_PROJECT_ID --region us-central1` should
      answer `Listed 0 items.`
- [ ] ~~**Streaming.** Every Dataflow job drained or cancelled, every feeding Cloud Scheduler job
      deleted or paused.~~ No streaming resource is created. A Data Fusion pipeline can be given a
      schedule, and none of tonight's four is.
- [ ] ~~**Serving.** Every Vertex AI endpoint undeployed.~~ No serving resource is created.
- [ ] **Managed services with an hourly floor. This is the row that matters.** The Cloud Data Fusion
      instance is deleted. Step 12 performs this in front of the room; do it again after class if the
      demonstration stopped earlier.
      `gcloud beta data-fusion instances delete <INSTANCE> --project YOUR_PROJECT_ID --location us-central1 --quiet`
      Confirm with `gcloud beta data-fusion instances list --project YOUR_PROJECT_ID --location us-central1`,
      which must answer `Listed 0 items.` **A deleted instance is the only safe state. A stopped one
      is not a state Data Fusion offers.** No Composer or Managed Airflow environment is created by
      this demonstration, and no Persistent History Server.
- [ ] ~~**Networking.** Forwarding rules, static external IPs, Cloud NAT gateways.~~ Nothing here has
      a network endpoint the demonstration created. The instance's tenant project holds one and it is
      removed with the instance.
- [ ] **Storage. Check for four buckets, expect to delete three.** The demo bucket
      `dsba6190-pos-<SUFFIX>` is deleted. **Dataproc creates two more that nobody asked for**, named
      `dataproc-staging-us-central1-<PROJECT_NUMBER>-<hash>` and
      `dataproc-temp-us-central1-<PROJECT_NUMBER>-<hash>`, on the first run that provisions a
      cluster. **Deleting the cluster does not remove them and neither does deleting the instance.**
      They hold almost nothing and cost almost nothing, and they are still two objects this
      demonstration created and did not declare.

      **Data Fusion creates a fourth**, named `df-<digits>-<hash>` and labelled
      `cdf_instance=<INSTANCE>`. On the 10 September teardown that one was removed with the instance,
      so it usually needs no action. Check for it anyway, because it carries no name this
      demonstration chose and nothing else in the project will identify it:

      ```sh
      gcloud storage ls --project YOUR_PROJECT_ID
      gcloud storage buckets list --project YOUR_PROJECT_ID \
        --filter="labels.cdf_instance=<INSTANCE>" --format="value(name)"
      ```

      Delete what those list, **except anything belonging to another demonstration**. On a shared
      demo project the listing includes buckets this session did not create, and the two Dataproc
      ones are regional rather than per-session: confirm no other Data Fusion or Dataproc work is
      running before removing them. No retention policy is set anywhere, so no delete is refused.
- [ ] ~~**Keys.** Cloud KMS key versions scheduled for destruction.~~ No customer-managed key is used.
      Everything written tonight carries Google-managed encryption.
- [ ] **BigQuery.** Dataset `dsba6190_sales_<SUFFIX>` dropped, with its one table.
      `bq --project_id=YOUR_PROJECT_ID rm -r -f -d dsba6190_sales_<SUFFIX>`. Confirm with
      `bq --project_id=YOUR_PROJECT_ID ls`, which should list only `analytics_demo`, a
      pre-existing dataset this demonstration does not touch. No model is trained, so nothing bills
      as storage after the table is gone.
- [ ] ~~**Registry.** Demo images deleted from Artifact Registry.~~ No image is built.
- [ ] **Verify against billing, next morning.** Billing → Reports, filtered to the demo project,
      grouped by service, for yesterday. Confirm the charge matches what this runbook predicted, and
      write the actual figure into the cost line above. A predicted number that is never checked is
      an estimate forever. Expect four lines: Cloud Data Fusion at zero if the 120 free
      instance-hours are unconsumed and about $1.80 per hour if they are not, Compute Engine and
      Dataproc at a few cents for the clusters, Cloud Storage at a fraction of a cent, and BigQuery
      at zero against the free allowance. **Check this one even if you check no other**, because it
      is the only evidence that the instance is actually gone rather than merely reported gone.
- [ ] **Budget alert still armed.** Confirm the project budget and its alert threshold are unchanged.
      The $50 monthly budget on `YOUR_PROJECT_ID` would catch a forgotten instance on about day
      two, which is $60 of warning rather than $1,296 of invoice.
- [ ] **The IAM grants stay.** Three bindings survive teardown by design:
      `roles/datafusion.serviceAgent` on the default compute service account,
      `roles/iam.serviceAccountUser` for the Data Fusion service agent on that same account, and the
      pre-existing `roles/editor`. They cost nothing, `live-setup.sh` expects them, and removing them
      only guarantees the next rehearsal rediscovers the same two failures.
- [ ] **Anything that could not be destroyed** is written here, with the reason and a date to revisit.
      As of 10 September 2026 that list is: four enabled APIs, `datafusion`, `dataproc`, `storage`
      and `bigquery`, which are free to leave on and which `live-setup.sh` expects; and the three IAM
      bindings above. Nothing else survives.

---

## If it fails live

| What happened | Do this |
|---|---|
| A run fails about five seconds in, at `PROVISION` | An IAM grant is missing. Both are in the before-class table with the exact command. Do not debug the pipeline; the pipeline is fine |
| A run fails for no stated reason on its first attempt | Google's own Lab 6 note says a Data Fusion pipeline can fail spuriously and the remedy is to re-run. Re-run it once. **This costs ten minutes the hour does not have**, so drop step 11's lineage tour and present slides 51 and 52 instead |
| A run fails in about two minutes with `does not have enough resources available` | A zone stockout. Pin a different zone with the namespace preference in the before-class table and re-run. If it fails again, present that step from `capture/` |
| A run is still `STARTING` after eight minutes | Dataproc is slow or short of capacity in the zone. Keep teaching. If it passes twelve minutes, abandon it and move to `capture/`; the argument does not depend on tonight's run |
| The Studio will not load, or loads an empty namespace | The browser is signed in as a different account. Open it in the profile matching `gcloud config get-value account`. If that fails, run the whole hour from the terminal; every step below step 3 has a command form |
| Wrangler's recipe panel is empty after the clicks | The workspace lost its connection. Do not rebuild it live. Show `capture/06-wrangler-recipe.txt`, which is the same thirteen directives, and say the run is recorded |
| The quarantine sink writes nothing | The error port was connected to the wrong node, or `on-error` is still `skip-error`. Both are visible in the deployed pipeline's JSON. Present `capture/25-quarantine-contents.txt` rather than rebuilding the branch |
| `bq` reports the table does not exist | Step 10 dropped it and the run that recreates it has not finished. Wait, or read the run state first |
| `Bytes Processed` reads `0` on a count | The job was answered from cache. Every command above already carries `--nouse_cache` |
| Credentials expired mid-session | Do not debug in front of the room. `gcloud auth login`, or move to `capture/` and say the run is recorded |
| The instance is not `RUNNING` at 1:30 | Do not attempt to create one. It takes about sixteen minutes. Run the whole hour from `capture/` and say plainly that the instance failed to provision, which is itself the session's cost-and-lead-time argument made the hard way |
| The hour runs out at step 11 | **Skip to the teardown.** Step 12's row count is on slide 51 and in `capture/29-count-doubled.txt`, and the deletion is not optional. Never end this session with the instance running |

The captured output is not a lesser version of this demonstration. It is the same run, recorded on
10 September 2026, and every line is real. Switching to it costs the room nothing except the sight
of
a pipeline being built.

---

## What is staged where

`live-setup.sh` writes all of these into the working directory before class. Nothing is applied
except the instance, the bucket, the dataset and the clean extract.

| Path | Step | What it is |
|---|---|---|
| `env.sh` | all | `PROJECT`, `BUCKET`, `DATASET`, `FQ`, `ENDPOINT`, so no command needs a name typed by hand |
| `sample/pos-2026-09-24.csv` | 4 | 20,000 well-formed transactions, 1,131,128 bytes |
| `sample/pos-2026-09-24-dirty.csv` | 7 | The same rows plus the three the source should not have sent, 1,131,286 bytes |
| `pipelines/01-baseline.json` | 3 and 4 | GCS source, Wrangler, BigQuery sink. `on-error` is `skip-error` |
| `pipelines/02-quarantine.json` | 10 | The same, plus the error collector and the GCS error sink |
| `pipelines/03-idempotent.json` | 12 | The same as 02, with **both** sinks made safe to run twice: `truncateTable` on BigQuery, and a run-scoped prefix on the error sink |
| `pipelines/04-drift.json` | capture | One directive removed, so a string reaches a numeric column |

**The pipeline definitions are generated, not committed as-is.** `pipelines/make-pipelines.py`
writes
them against the plugin versions the instance reports, because `google-cloud` was 0.24.1 and
`wrangler-transform` was 4.11.1 on 10 September and a pipeline pinned to a version the instance does
not carry fails at deploy rather than at run. Regenerating is one command and it is what
`live-setup.sh` does.

**A placeholder copy is checked in beside the generator**, carrying `PROJECT_ID`, `BUCKET_NAME` and
`DATASET_NAME` where the real identifiers go. It exists for one situation: the Studio has moved, a
node is not where step 3 or step 10 says it is, and rebuilding by hand in front of the room is not
an option. Substitute three strings and import the JSON. Say out loud that the pipeline was imported
rather than built, because the room is owed that.

**Two things are deliberately not automated.** The Wrangler recipe is built by clicking in step 2,
because watching thirteen clicks become thirteen lines of code is the step's entire argument, and
importing the JSON would skip it. The quarantine branch is drawn on the canvas in step 10 for the
same reason. Both have a JSON form beside them, and the JSON is the fallback rather than the plan.

---

## Where the captured output is on the deck

Slide 38 introduces Crown Street Markets. Slides 39 and 40 carry the twelve-step run sheet with its minute budgets, split across two slides by
the converter. Slides 41 to 52 carry one capture slide per step, each a listing of real output
trimmed to render at 28px or larger, with the capture date and the source directory named in its
speaker notes. Slide 37 is the `Live Demonstration · 60 Minutes` divider, which exists so the twelve
capture slides inherit the demonstration's kicker rather than Hour 2's.

| Step | Deck slide | Captures authored onto it |
|---|---|---|
| 1 | 41 | `02-instance-ready.txt`, `03-instance-describe.txt` |
| 2 | 42 | `06-wrangler-recipe.txt` |
| 3 | 43 | `07-pipeline-shape.txt`, `08-deploy-baseline.txt` |
| 4 | 44 | `10-dataproc-cluster.txt` |
| 5 | 45 | `09-run1-wait.txt` |
| 6 | 46 | `12-count-after-run1.txt`, `13-nulls-after-run1.txt` |
| 7 | 47 | `14-dirty-rows.txt` |
| 8 | 48 | `20-quarantine-shape.txt` |
| 9 | 49 | `18-count-after-run2.txt`, `19-bad-rows-missing.txt` |
| 10 and 11 | 50 | `23-count-after-run3.txt`, `25-quarantine-contents.txt` |
| 12 | 51 | `28-run4-wait.txt`, `29-count-doubled.txt` |
| capture | 52 | `41-drift-error-log.txt`, `44-instance-hours.txt`, `46-instances-gone.txt` |

The last row is the schema-drift run, which is presented from the deck rather than performed. Steps
10 and 11 share a capture slide because they share a run. **`29-count-doubled.txt` is named for what
it was expected to show rather than what it shows**, and the file has been left under that name so
the capture numbering matches `capture.sh`. It shows 20,001 rows and 20,001 distinct transactions,
because the run that was supposed to double the table failed instead. The reason is in
`28-run4-wait.txt` and in the log line step 12 quotes.

The masked values stay masked. `capture.sh` replaces the authenticated account with
`instructor@example.edu`, the project number with `PROJECT_NUMBER`, and the per-instance tenant
hostname Data Fusion generates with a placeholder, and the deck carries them in that form.

**The numbers above are counted from the built PDF, not from the AsciiDoc headings.** The deck runs
to **73 slides** since the A6 scaffolding and the Crown Street scenario were added. The converter inserts nothing
into it, because Session 6 carries an authored `== Agenda` slide, but several headings split in two:
the run sheet at 39 and 40, the Failure Handling at 1,200 Stores table, and the three A6 criteria
and options tables. Verify
against `slides/pdf/Session_06_Data_Ingestion_and_Orchestration.pdf` before quoting a number here.
