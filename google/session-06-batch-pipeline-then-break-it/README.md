# Session 6 live demo · a batch pipeline, then break it

The hour-long Cloud Data Fusion demonstration from
[`../../lecture-06-ingestion-integration.md`](../../lecture-06-ingestion-integration.md), built as
runnable pipeline definitions and captured as real output.

**Captured 10 September 2026** against project `YOUR_PROJECT_ID` (UNC Charlotte Demo), Cloud
Data Fusion 6.11.1 Basic edition, Google Cloud SDK 584.0.0, plugins `google-cloud` 0.24.1,
`wrangler-transform` 4.11.1, `core-plugins` 2.13.1, on ephemeral Dataproc image 2.3.35-debian12.
Every line in `capture/` is real command output. Nothing is illustrated or reconstructed.

The run builds a point-of-sale ingest pipeline from a Cloud Storage source through a Wrangler
transform into a BigQuery sink, loads a clean day and records the row count, replaces the source
with
a day carrying three malformed rows, discovers in one query that two of them vanished without a
signal and that the row count doubled to 40,001, adds an error collector and a quarantine sink so
the
count reconciles, finds that the third bad row loaded anyway because a negative quantity is well
typed, traces one column
back to its source through field-level lineage, runs the same pipeline twice to produce duplicate
transactions, fixes that with a sink that replaces rather than appends, breaks the pipeline a second
way by letting a string reach a numeric column and capturing the sink's refusal, `Field 'amount' of
type 'string' is incompatible with column 'amount' of type 'double'`, and finishes by deleting the
instance and confirming that nothing remains.

**Cost is the subject of this demonstration rather than a footnote.** A Basic-edition instance bills
$1.80 per instance-hour with the first 120 instance-hours each month free per billing account. The
capture run measured **1.22 instance-hours** across seven pipeline runs, which is $0 on an
unconsumed allowance and about $2.20 otherwise. An in-class evening from T minus 60 to teardown is
about 2.5 instance-hours. Each pipeline run adds an ephemeral three-node Dataproc cluster for the
length of the run, at
roughly $0.04. **An instance left running costs $25.20 for one night and $1,296 for a month**, which
is more than every other demonstration in this course combined. The figure matches the Session 6 row
in [`../../../docs/DEMO-DEVELOPMENT-PLAN.md`](../../../docs/DEMO-DEVELOPMENT-PLAN.md) section 7.

## Why this demonstration is an hour

[`../teaching-notes.md`](../teaching-notes.md) records the finding that shapes this build:
**students
do not build a pipeline in Lab 6.** They deploy a pre-built sample from the Hub and press Run. The
notes state the consequence directly, and it is the reason this demonstration carries more weight
than any other in the term. It is not a preview of the lab; it is the other half of the session.

| Gap between Lab 6 and what A6 grades | Step that closes it |
|---|---|
| The lab deploys a pre-built pipeline. It never authors a source, a transform or a sink | 2 and 3 |
| The lab explains that a run provisions an ephemeral cluster. It never shows one | 4 and 5 |
| Malformed records, and what a transform does with them by default | 7, 8 and 9 |
| Quarantine branches and dead-letter paths appear in the lecture and in neither the lab nor its brief | 10 and 11 |
| Lineage is available in the UI and is not exercised by any lab task | 11 |
| Idempotency, and running the same pipeline twice on purpose | 9 and 12 |
| ETL versus ELT, which the lab never raises | 3 and 12 |
| The cost model, which A6 grades and the lab states in one sentence | 1, 5 and 12 |

## What the rehearsal changed

The step list in `DEMO-DEVELOPMENT-PLAN.md` section 5.2 was written before any of this had been run.
Four of its assumptions did not survive contact with the service, and each change is recorded here
rather than made quietly.

**A pipeline run takes seven and a half to nine and a half minutes, not the five to eight the plan
assumed.** The three runs that succeeded measured 454, 533 and 571 seconds.
Most of a run is not the work: the queue and the Dataproc cluster build dominate and the Spark job
over 20,000 rows is the smaller part. The plan budgeted six runs
inside sixty-one minutes; six runs alone are sixty minutes. **The hour now runs four**, each one
started before the material that covers it, and the runbook is written as start-then-teach pairs
rather than as a list of things to watch.

**The instance takes about sixteen minutes to provision, and two create attempts failed first.** Two
builds were measured on 10 September, at 16 minutes 46 seconds and 15 minutes 20 seconds, against
Google's stated ten and this course's stated fifteen to twenty-five. On the first build both earlier
`create` calls aborted after three seconds with `Failed to perform tenant project creation`, which
is
neither a permissions problem nor a quota problem, and the third attempt built normally. Staging
moves from T minus 60 as a comfortable margin to T minus 60 as a requirement.

**Two IAM grants are required and Lab 6 names only one of them.** The lab tells students to grant
the
Cloud Data Fusion API Service Agent role to the instance's Spark service account, and that grant is
genuinely required: without it a run fails five seconds in with a list of missing
`storage.objects.*` permissions, and `roles/editor` on the same account does not substitute for it.
The grant the lab does not mention is `roles/iam.serviceAccountUser` for the Data Fusion service
agent on that same account; without it the run fails five seconds in with `User not authorized to
act as service account`. Both are in `live-setup.sh` and both are in the runbook's failure table
with
the exact command. This is Week 2's material biting in Week 6, which the teaching notes predicted.

**The payload changed, and the rehearsal is the reason.** The plan expected the second identical run
to double the table. It does not. The second run **fails outright**, because the Cloud Storage error
sink added at step 10 writes a directory and a Hadoop output committer refuses to write into a
directory that already exists:

```
Stage 'QuarantineSink' encountered :
org.apache.hadoop.mapred.FileAlreadyExistsException:
Output directory gs://dsba6190-pos-75439/quarantine/pos already exists
```

That is a better payload than the doubling and it is captured in `capture/28-run4-wait.txt` and
`capture/29-count-doubled.txt`. **Idempotency is not one property of a pipeline. It is a property of
every sink in it.** The BigQuery sink would have appended and doubled the day; the Cloud Storage
sink
refused to run at all. The doubling is still demonstrated, at step 9, by the two runs of the
pipeline
that has no error sink: 20,000 rows then 40,001. And the control that made the count reconcile at
step 11 is the same control that made the pipeline un-runnable at step 12, which is the honest
version of the design conversation A6 asks for.

**The fix has two halves and the rehearsal proved that one is not enough.** `truncateTable` on the
BigQuery sink was the only change the first pass made, and `capture/33-run5-wait.txt` shows that
repair failing after 563 seconds with the identical `FileAlreadyExistsException` on the identical
sink, and `capture/35-run6-wait.txt` shows it failing again at 400 seconds. **The same defect twice,
after a repair.** A fix that addresses the defect you noticed and not the one you did not is the
ordinary shape of a 3 a.m. repair. The committed `pipelines/03-idempotent.json` therefore carries
both halves: the
BigQuery sink truncates, and the error sink writes
`quarantine/pos/dt=${logicalStartTime(yyyy-MM-dd-HHmmss)}` rather than one fixed directory. That is
the deterministic partition target Concept Block 1 already teaches, applied to the sink nobody
thinks
of. **The captures show the version that fixed only one sink**, because that is what ran, and the
runbook says so where it names the fix.

**The captured Airflow failure is replaced by a captured Data Fusion failure.** The plan made step
10
a capture because a Managed Airflow environment takes fifteen to twenty-five minutes to create and
costs $0.30 to $0.60 an hour for one failed task. That reasoning still holds and the environment is
still not built. What replaced it is a failure in the tool the room has been watching for fifty
minutes: one directive removed from the recipe, so the source's amount column reaches a `FLOAT64`
column as a string and the sink refuses the load. It is captured for the same kind of reason, stated
plainly in the runbook: an eighth pipeline run does not fit in the hour. It is a better step because
it needs no second service, because the error is one students will meet in Lab 6, and because it is
the exact counterpart to step 9. The same class of defect, handled loudly instead of silently.

The Airflow argument the plan wanted from that step survives in step 12, made against the room's own
evidence rather than a screenshot. Students have watched the same pipeline run twice and double a
table. The lab's DAG sets `'retries': 1` on every task, and asking what that setting would have done
to the table they are looking at lands harder than a picture of somebody else's failed task.

**Three smaller corrections.** There is no GA `gcloud data-fusion`; every command is
`gcloud beta data-fusion` and `gcloud components install beta` is a prerequisite. `describe` returns
`NOT_FOUND` while a create is in flight, so `operations list` is the command that shows progress.
And
the ephemeral cluster is three `e2-custom-2-8192` nodes rather than the three `n1-standard-4` the
plan's cost basis assumed, which makes a run cost about $0.04 rather than about $0.10.

## Layout

| Path | What it is |
|---|---|
| `pipelines/make-pipelines.py` | Emits the four pipeline definitions, pinned to the plugin versions the instance reports |
| `pipelines/0*.json` | The same four, written with `PROJECT_ID`, `BUCKET_NAME` and `DATASET_NAME` in place of real identifiers, so a pipeline can be imported into the Studio rather than rebuilt |
| `sample/make-sample.py` | The seeded generator for two point-of-sale extracts that differ by three rows |
| `cdap.py` | Drives the instance through its CDAP REST API: deploy, start, wait, logs, stage metrics, lineage |
| `capture/` | Full real output, one file per command |
| `capture.sh` | The headless recorder. Re-runnable, self-cleaning through an exit trap |
| `live-setup.sh` | Provisions the instance and blocks until it runs. **Applies. Never destroys** |
| `RUNBOOK.md` | The instructor document |
| `prep.ipynb`, `demo.ipynb` | Bash notebooks, commands only. `prep` is T minus 60 to T minus 30; `demo` is steps 1 to 12 and the teardown. Needs the Bash kernel (`bash_kernel`). What to say stays in `RUNBOOK.md` |
| `build-notebook.py` | Regenerates both notebooks. Edit the generator, not the notebooks |
| `build-runbook-pdf.py` | WeasyPrint, Charlotte brand, podium sizing |

## Three things this demo does that Session 5 does not

**The artifact is JSON, not HCL.** A Data Fusion pipeline is a JSON document and the Studio canvas
is
a renderer for it. Everything the Studio does over the wire is a call to the v3 CDAP REST API, which
is what lets an hour of clicking be captured as text. The demonstration is performed in the browser
because the canvas, the Wrangler grid and the lineage view are visual teaching. The capture is
performed over REST because a screenshot cannot be diffed and a log line can.

**The numbers reproduce.** `sample/make-sample.py` is seeded, so both extracts are byte-identical on
every run, and the two independent rehearsals on 10 September returned the same 20,000 rows and the
same $2,422,034.45 from the clean day. A figure quoted on a slide is a figure the next re-capture
will also produce.

**The pipeline definitions are generated, and a placeholder copy is committed beside the
generator.**
`google-cloud` was 0.24.1 and `wrangler-transform` 4.11.1 on 10 September, and a pipeline pinned to
a
version the instance does not carry fails at deploy, so `make-pipelines.py` reads the versions off
the instance and writes the four variants against them. That is what `live-setup.sh` runs. The four
JSON files checked in beside it carry `PROJECT_ID`, `BUCKET_NAME` and `DATASET_NAME` where the real
identifiers go, and exist for one purpose: if the Studio has moved and a node cannot be found where
the runbook says it is, the pipeline can be imported instead of rebuilt. Substitute three strings
and
import. The four differ from each other by exactly one design decision each, which is what makes the
diffs teachable.

**Waiting is the demonstration's main cost, and the runbook treats it as content.** Every other
session in this course runs a command and reads an answer. Here the queue and the Dataproc cluster
build take most of a run and cannot be shortened, so each of the four runs is started before the
block of teaching that covers it, and the runbook names which run is in flight during which step.

## Re-capture

```sh
./capture.sh YOUR_PROJECT_ID
```

The name suffix is derived per run, so a re-capture does not collide with a previous one in the
global bucket namespace. **The run takes about ninety minutes**: sixteen for the instance, seven
pipeline runs, and a few minutes for queries and teardown. Re-run before
class if the instance version has moved, because plugin properties gain and lose names between
releases and the runbook quotes pipeline JSON literally.

A second pass against an instance that is already running should not pay for a third one:

```sh
DSBA_REUSE_INSTANCE=<name> DSBA_REUSE_BUCKET=<bucket> \
DSBA_REUSE_DATASET=<dataset> DSBA_REUSE_SECONDS=<n> ./capture.sh YOUR_PROJECT_ID
```

**The recorder runs seven pipelines and the hour runs four**, and the four are the recorder's runs 1
through 4. The three extra runs prove the two arguments the hour makes from the captures instead:
that the `truncateTable` fix produces the same count however many times it runs, and that a schema
change fails loudly where a bad value failed silently. The hour ends on the defect rather than the
repair, deliberately, because the defect is what A6 asks students to design against.

**The exit trap is the most important part of this script.** It deletes the Data Fusion instance
first, then any surviving Dataproc cluster, then the dataset, then the demo bucket, then the buckets
nobody asked for: the two Dataproc writes on its first cluster, and the one Data Fusion writes for
the instance. That last one, `df-<digits>-<hash>`, was removed with the instance on the 10 September
teardown, so the trap's pass over it is usually a no-op; it is there because the bucket carries no
name this demonstration chose and only the `cdf_instance` label identifies it. It fires on every exit path including an interrupt and
including a failure partway through. An earlier capture attempt on 10 September was killed mid-run
and the trap deleted the instance correctly, which is the behaviour to preserve in any edit to this
file.

## What each capture is for

| File | Step | The teaching moment |
|---|---|---|
| `01-instance-create.txt` | 1 | The create returns an operation, not an instance |
| `02-instance-ready.txt` | 1 | **15 minutes 20 seconds** on this run, and 16:46 on the first. Measured rather than estimated |
| `03-instance-describe.txt` | 1 | `state: RUNNING`, `type: BASIC`, and the meter that started at create |
| `04-compute-sa-roles.txt` | 1 | The two roles the cluster's identity needs, one of which Editor does not imply |
| `04b-act-as.txt` | 1 | The grant Lab 6 does not mention |
| `05-artifacts.txt` | 1 | The four plugin versions the pipelines are pinned against |
| `06-wrangler-recipe.txt` | 2 | **Thirteen clicks, thirteen lines of code** |
| `07-pipeline-shape.txt` | 3 | Three nodes, two edges, and a directed acyclic graph |
| `08-deploy-baseline.txt` | 3 | Deployed, and nothing has run |
| `09-run1-wait.txt` | 5 | Four phases: 189s queued, 110s building a cluster, 156s of Spark |
| `10-dataproc-cluster.txt` | 4 | **The cluster nobody asked for**, three `e2-custom-2-8192` nodes |
| `11-run1-stages.txt` | 4 and 6 | **20,001 records out of the source for a 20,000-row file.** The header is a line too |
| `12-count-after-run1.txt` | 6 | 20,000 rows and 2,422,034.45. The control number |
| `13-nulls-after-run1.txt` | 6 | What a clean run looks like, so the unclean one is recognisable |
| `14-dirty-rows.txt` | 7 | Three rows, three different ways to be wrong |
| `15-dirty-object.txt` | 7 | The same object key, 158 bytes larger |
| `16-run2-wait.txt` | 8 | 571 seconds, and it succeeded. **That it succeeded is the problem** |
| `17-run2-stages.txt` | 9 | **20,004 in, 20,001 out.** Three records lost inside one stage, with no signal |
| `18-count-after-run2.txt` | 9 | **40,001.** Every transaction from the clean day is in the warehouse twice |
| `19-bad-rows-missing.txt` | 9 | **Two of three bad rows gone with no signal. The third loaded, with `qty = -4`** |
| `20-quarantine-shape.txt` | 10 | Two stages, two edges, and one property |
| `21-deploy-quarantine.txt` | 10 | Five stages now |
| `22-run3-wait.txt` | 10 | 534 seconds, with the branch attached |
| `23-count-after-run3.txt` | 11 | **20,001, and 20,001 plus 2 quarantined is the 20,003 in the file** |
| `24-quarantine-listing.txt` | 11 | A prefix that did not exist an hour ago |
| `25-quarantine-contents.txt` | 11 | **The row, its byte offset, the stage that rejected it, and the directive that raised the error** |
| `26-lineage-fields.txt` | 11 | Six fields, every one carrying recorded lineage |
| `27-lineage-amount.txt` | 11 | The workflow run and the operations that produced `amount` |
| `28-run4-wait.txt` | 12 | **`FAILED` at 392 seconds.** The run that changes nothing and cannot happen twice |
| `29-count-doubled.txt` | 12 | **20,001 rows, 20,001 distinct.** Named for what it was expected to show; the run that would have doubled the table failed first |
| `30-duplicate-detail.txt` | 12 | Every transaction counted once, because the second run never landed |
| `31-idempotent-diff.txt` | 12 | **One property, and the rehearsal proved one is not enough.** The committed JSON carries both halves |
| `32-deploy-idempotent.txt` | skipped live | Deployed |
| `33-run5-wait.txt` | skipped live | **`FAILED` at 563 seconds, on the same sink.** Fixing one sink is not fixing the pipeline |
| `34-count-stable.txt` | skipped live | The table after the repair that did not complete |
| `35-run6-wait.txt` | skipped live | **`FAILED` at 400 seconds.** The same defect, twice, on the same sink |
| `36-count-still-stable.txt` | skipped live | 20,001 after both attempts, because neither completed |
| `37-drift-diff.txt` | capture | One directive removed |
| `38-bq-schema.txt` | capture | The column is `FLOAT`, and it already exists |
| `39-deploy-drift.txt` | capture | It deploys. Nothing is validated yet |
| `40-run7-failed.txt` | capture | **`FAILED` at 361 seconds**, faster than any successful run, because the sink validates before it writes |
| `41-drift-error-log.txt` | capture | **`Field 'amount' of type 'string' is incompatible with column 'amount' of type 'double'`.** The field, both types, and the table |
| `42-count-after-failure.txt` | capture | **Still 20,001.** A pipeline that halts leaves the warehouse in the state it was in |
| `43-all-runs.txt` | 12 | Every run of the evening, in one list |
| `44-instance-hours.txt` | 12 | Instance-hours consumed, against the 120 free ones |
| `45-instance-delete.txt` | 12 | The most important command in this directory |
| `46-instances-gone.txt` | 12 | **`Listed 0 items.`** |
| `47-dataproc-gone.txt` | 12 | No cluster survives a run |
| `47b-dataproc-buckets.txt` | 12 | **The two Dataproc buckets, found before they are removed.** Neither the cluster deletion nor the instance deletion had touched them |
| `48-bq-gone.txt` | 12 | Only `analytics_demo`, which this demonstration does not touch |
| `49-storage-gone.txt` | 12 | Every bucket this demonstration created is gone. The two that remain belong to a different build running in the same project that evening |

## Step 11's schema-drift run is a capture step, and time is why

`DEMO-DEVELOPMENT-PLAN.md` section 5.2 made step 10 a capture because a Managed Airflow environment
takes fifteen to twenty-five minutes to create and costs $0.30 to $0.60 an hour to produce one
failed
task. That reasoning is sound and the environment was not built.

The step that replaced it is a capture for a different measured reason. A pipeline run takes ten
minutes, the hour holds four, and the schema-drift run would be the eighth. It is recorded in
`capture/39` through `capture/42`, presented from the deck at slide 52, and labelled as a capture in
its slide title. That is the repository standard applied to itself: a captured run beats an
illustration, and a capture states its date and its versions.

## The account, the project number and the tenant host are masked

`capture.sh` runs a masking pass over every file before it finishes. It replaces the authenticated
account with `instructor@example.edu`, the project number with `PROJECT_NUMBER`, the per-instance
tenant hostname Data Fusion generates with a placeholder, and the home directory with `~`. The
project id stays, because it is on every slide and the runbook quotes it. Nothing in the
demonstration generates a secret, and the invented transactions describe forty stores that do not
exist.

## Performing it live

[`Session-06-Live-Demo-Runbook.pdf`](Session-06-Live-Demo-Runbook.pdf) is the document to hold while
teaching. It is built from [`RUNBOOK.md`](RUNBOOK.md) by `python3 build-runbook-pdf.py`, so edit the
markdown and rebuild rather than the PDF. It carries pre-class setup with real T-minus timings, the
twelve steps with exact commands, real expected output and what to notice, which run is in flight
during which step, the teardown checklist, and what to do when something fails in front of the room.

Stage with [`live-setup.sh`](live-setup.sh) **sixty minutes before class, not thirty.** The margin
is
not comfort. The instance took about sixteen minutes to build on 10 September, measured twice, and
two create
attempts failed before one of those builds started.

**Do not run `capture.sh` in class.** It deletes the instance through an exit trap, and rebuilding
one takes about sixteen minutes.

## Teardown is step 12, and it is the point

Session 5's teardown protected against a fraction of a cent. This one protects against $1,296 a
month. The instance is deleted in front of the room, the deletion is confirmed with
`gcloud beta data-fusion instances list`, and the overnight number is said out loud twice: once at
step 1 when the meter is introduced and once at step 12 when it stops.

Three things survive teardown on purpose and are listed in the runbook's checklist with the reason
attached: four enabled APIs, and the two IAM bindings the rehearsal proved are required. Everything
else is removed, including the two Dataproc buckets, which neither the cluster deletion nor the
instance deletion removes. A fourth bucket, the instance's own `df-<digits>-<hash>`, went with the
instance on 10 September; the checklist still asks after it, because it carries no name this
demonstration chose.
