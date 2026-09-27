# Session 5 demonstration · Build and harden a lake

This demonstration accompanies Session 5, Cloud Storage and Data Lakes. Catawba Precision
Components, a fictional parts manufacturer with plants around Charlotte, builds the data lake its
plant telemetry lands in. The run places a governed bucket beside an ungoverned one and then tests
each governance control by trying to break it. It makes a bucket public, overwrites and deletes an
object, deletes a record under a retention policy, and disables an encryption key. It also measures
what file format and partitioning save in BigQuery.

Every command was run end to end on 10 September 2026 with Terraform v1.5.7, the `hashicorp/google`
provider v5.45.2 and Google Cloud SDK 584.0.0, and `capture/` holds the real output of each one. The
captures replace the authenticated account with a placeholder address and the project number with
`PROJECT_NUMBER`. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 2 | The governed bucket reports public access prevention `enforced`, uniform access `true`, versioning and four labels. The ungoverned bucket reports `inherited`, `false` and no labels | `04`, `05` |
| 3 | Five zone prefixes exist, and none of them is a directory | `06`, `08` |
| 4 | An anonymous `curl` fetched a file from the ungoverned bucket. The governed bucket refused the same grant with `412` and a per-object grant with `400` | `10`, `11`, `12` |
| 5 | An overwrite and a delete were both undone from a prior generation. Three generations survived the delete | `16`, `21`, `22` |
| 6 | CSV is 11.78 MiB and Parquet 2.56 MiB for the same 200,000 rows. BigQuery processed 12,348,283 bytes from the CSV and 1,600,000 from the Parquet, with the same answer | `24`, `27`, `29` |
| 8 | Deleting a record under a one-hour retention policy failed with `403` | `36` |
| 9 | With the key version disabled, both a read and a write failed with `KEY_DISABLED`. Re-enabling the key restored the read | `42`, `43`, `45` |
| 10 | A query on one day of ten partitions processed 160,000 bytes against 1,600,000 for all ten | `50`, `52` |
| 11 | The project has no organization above it, and setting an organization policy was denied | `53`, `57` |
| 12 | `terraform destroy` removed seven resources and failed on the eighth, the retention bucket. It succeeded after the retention period was cleared | `58`, `60` |

## Known issues and fixes

- A read can succeed for a few seconds after the key version is disabled, because Cloud Storage can
  serve it from a cached key. The step 9 script polls the read until it refuses. A write refuses as
  soon as the key is disabled.
- BigQuery bills a 10 MB minimum per table scanned. At this size both formats bill about the same,
  so compare the `Bytes Processed` column rather than `Bytes Billed`.
- If more than an hour passes between steps 8 and 12, the retention period expires and the first
  destroy succeeds. `capture/58-destroy-refused.txt` holds the refusal.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `01-plain/` to `07-partitioned/` | The Terraform for each stage, from the ungoverned baseline to the partitioned table |
| `sample/make-sample.py` | Generates 200,000 rows of seeded telemetry in three layouts |
| `steps/` | One Bash script per step, and `menu.sh`, which runs them from a menu |
| `live-setup.sh` | Stages the working directory, applies the ungoverned baseline and creates the key. It never deletes anything |
| `capture.sh`, `capture/` | The recorder and its 60 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
