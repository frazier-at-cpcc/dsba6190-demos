# Session 6 demonstration · A batch pipeline, then break it

This demonstration accompanies Session 6, Ingestion and Integration. Crown Street Markets, a
fictional Charlotte grocery chain with 40 stores, builds the nightly pipeline that turns each
store's point-of-sale extract into the validated sales table its managers read at 7 a.m. The
pipeline runs in Cloud Data Fusion from a Cloud Storage source, through a Wrangler transform, into a
BigQuery sink.

The demonstration loads a clean day, then a day carrying three malformed rows. One query finds two
defects: two bad rows vanished without a signal, and the table doubled to 40,001 rows. An error
collector and a quarantine sink make the count reconcile. Field-level lineage traces one column back
to its source. A second identical run then fails, because the quarantine sink cannot write twice.
The recorded output also shows a schema change that the BigQuery sink refuses loudly.

Every command was run end to end on 10 September 2026, and `capture/` holds the real output of each
one. The run used Cloud Data Fusion 6.11.1 Basic edition, Google Cloud SDK 584.0.0, `google-cloud`
0.24.1, `wrangler-transform` 4.11.1 and `core-plugins` 2.13.1. Read `RUNBOOK.md` for the
walkthrough.

## Cost

The Data Fusion instance is the most expensive resource in any demonstration in this course. Basic
edition bills $1.80 per instance-hour from the moment the instance is created, whether or not a
pipeline runs. The first 120 instance-hours each month are free per billing account. The recorded
run consumed 1.22 instance-hours across seven pipeline runs, which is $0 on an unused allowance and
about $2.20 otherwise. Following the notebooks by hand takes two to three instance-hours, about $4.
Each pipeline run adds an ephemeral Dataproc cluster at about $0.04.

An instance left running costs $25.20 for one night and $1,296 for a month. The instance took 15
minutes 20 seconds to provision on the recorded run and 16 minutes 46 seconds on an earlier build.
Delete it the same day you create it, and confirm the deletion.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | The instance reached `RUNNING` 920 seconds after `create` | `02` |
| 2 | Thirteen clicks in Wrangler produced a thirteen-line directive recipe | `06` |
| 4 | Each run built a three-node `e2-custom-2-8192` Dataproc cluster that nobody requested | `10` |
| 5 | Run A took 454 s: 189 s queued, 110 s building the cluster, 156 s of Spark | `09` |
| 6 | The clean day loaded 20,000 rows totalling 2,422,034.45 | `12` |
| 9 | Wrangler took in 20,004 records and emitted 20,001, and the table held 40,001 rows | `17`, `18` |
| 9 | Two bad rows disappeared with no signal, and the row with `qty = -4` loaded | `19` |
| 11 | 20,001 loaded rows plus 2 quarantined rows equal the 20,003 rows in the file | `23`, `25` |
| 12 | The unchanged second run failed at 392 s with `FileAlreadyExistsException` on the quarantine sink | `28` |
| After 12 | Fixing only the BigQuery sink failed again, at 563 s and at 400 s | `31`, `33`, `35` |
| After 12 | The schema-drift run failed at 361 s and left the table at 20,001 rows | `40`, `41`, `42` |
| Teardown | The instance list returned `Listed 0 items.` | `46` |

## Known issues and fixes

- There is no GA `gcloud data-fusion` command group. Install the beta components with
  `gcloud components install beta` and use `gcloud beta data-fusion`.
- A `create` can abort after three seconds with `Failed to perform tenant project creation`. This is
  not a permissions or quota problem. Re-issue the identical command. `live-setup.sh` does this
  automatically.
- A pipeline run needs two IAM grants beyond Editor. Without either one, the run fails about five
  seconds in, at `PROVISION`. `live-setup.sh` makes both grants.
- The Cloud Storage error sink writes a fixed directory, so the quarantine pipeline cannot run twice.
  `pipelines/03-idempotent.json` fixes both sinks. The captures show the earlier version that fixed
  only the BigQuery sink, because that version is the one that ran.
- `29-count-doubled.txt` keeps its original name. It shows 20,001 rows, not a doubled table, because
  the run that would have doubled the table failed first.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `sample/make-sample.py` | Generates the two seeded point-of-sale extracts, which differ by three rows |
| `pipelines/make-pipelines.py` | Writes the four pipeline definitions, pinned to the plugin versions the instance reports |
| `pipelines/0*.json` | The same four definitions with `PROJECT_ID`, `BUCKET_NAME` and `DATASET_NAME` placeholders, ready to import into the Studio |
| `cdap.py` | Drives the instance through its CDAP REST API: deploy, start, wait, logs, stage metrics and lineage |
| `live-setup.sh` | Provisions the instance and waits until it runs. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 51 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
