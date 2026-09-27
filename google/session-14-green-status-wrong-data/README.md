# Session 14 demonstration · Green status, wrong data

This demonstration accompanies Session 14, Production Readiness and FinOps. Crown Street Markets,
the fictional 40-store Charlotte grocery chain used across the course, loads last night's register
baskets into BigQuery for its replenishment dashboard. The load reports `DONE` every time, and the
data still goes wrong three ways. The demonstration adds four data checks in SQL, turns one of them
into a symptom alert, measures an error budget, restores a mistaken delete with time travel, and
finds the cheapest cost fix by label.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | The load wrote 12,270 rows with state `DONE` and no errors | `02` |
| 2 | All four checks returned green. Each run billed 30 MB, three 10 MB minimums | `04` |
| 3 | Three loads succeeded. The checks caught 377 rows at 3 per cent of the trailing mean, an extra `basket_total` column, and a 19.2 per cent null rate while the mean stayed at $45.50 | `06`, `08`, `11`, `12` |
| 4 | One RED entry was written at severity `ERROR` and counted by the log-based metric | `19`, `20`, `23` |
| 5 | Job status spent 297 bad minutes, 69 per cent of a 432-minute budget. The data spent 737, or 171 per cent | `22` |
| 6 | A delete removed 12,270 rows, and the restore returned them nine seconds later. The RPO was zero rows | `24` to `28` |
| 7 | The dashboard query processed 24.0 MB as written and 2.8 MB for the same answer. The checks billed 270 MB | `30` to `32` |
| 7 | The oldest raw file moved to Nearline, and its `gs://` URL did not change | `34`, `35` |
| 8 | Every resource type counted zero for the run's suffix | `40` |

## Known issues and fixes

- `bq` reads a query that opens with a `--` comment as a command-line flag. The `q` helper passes
  every query with a leading space to prevent this.
- A new log-based metric can take more than a minute to become visible to Cloud Monitoring. The
  alerting-policy cell retries every 30 seconds until it does.
- BigQuery refuses `INSERT INTO t SELECT * FROM t FOR SYSTEM_TIME AS OF ...`, because one statement
  cannot read a table at two snapshot times. The restore in step 6 goes through a temporary table.
- A `gcloud storage cat | head` pipe fails its hash check. Step 7 reads the file with `sed -n 1,3p`,
  which consumes the whole object.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `sample/make-store-sales.py` | Generates sixty nights, 738,708 rows, three incoming files and thirty load outcomes from a fixed seed |
| `sql/`, `monitoring/`, `lib.sh` | The checks, the error budget, the metric, the policy, the lifecycle rule, and the helpers |
| `live-setup.sh` | Stages the bucket and the table. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 41 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
