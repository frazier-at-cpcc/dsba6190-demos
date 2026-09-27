# Session 14 live demo · green status, wrong data

The 40-minute observability, reliability and FinOps demonstration for Session 14, Production
Readiness, Observability and FinOps, taught Thursday 19 November 2026. Crown Street Markets, the
fictional 40-store Charlotte grocery chain from Sessions 2, 6, 11 and 12, loads last night's register
baskets into BigQuery for its replenishment dashboard. The load reports `DONE` every time, and the
data goes wrong three ways.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`. The full
`prep.ipynb` and `demo.ipynb` run on the Bash kernel matched the captures.

## What the rehearsal changed

- **`bq` read a query that opens with a `--` comment as a command-line flag.** `q` now passes every
  query with a leading space.
- **A new log-based metric took more than a minute to become visible to Cloud Monitoring**, and the
  first alerting-policy attempt failed with "Cannot find metric(s)". The policy cell now retries every
  30 seconds.
- **`INSERT INTO t SELECT * FROM t FOR SYSTEM_TIME AS OF ...` is refused**, because one statement
  cannot read a table at two snapshot times. The restore goes through a temporary table.
- **A `gcloud storage cat | head` pipe failed its hash check.** The step reads the file with
  `sed -n 1,3p`, which consumes the whole object.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 1 | 12,270 rows loaded, state `DONE`, errors none | `02` |
| 2 | Four checks green; each run bills 30 MB, three 10 MB minimums | `04` |
| 3 | 377 rows, 3 per cent of the trailing mean; `extra basket_total`; null rate 19.2 per cent with the mean unchanged at $45.50 | `06`, `08`, `11`, `12` |
| 4 | One RED entry at severity `ERROR`, counted by the log-based metric | `19`, `20`, `23` |
| 5 | 297 bad minutes on job status, 69 per cent of a 432-minute budget; 737 on the data, 171 per cent | `22` |
| 6 | 12,270 rows deleted and restored nine seconds later; RPO zero rows | `24` to `28` |
| 7 | Dashboard query 24.0 MB processed against 2.8 MB for the same answer; checks billed 270 MB | `30` to `32` |
| 7 | Oldest raw file moved to Nearline; the `gs://` URL unchanged | `34`, `35` |
| 8 | Every resource type counts zero for the run's suffix | `40` |

## Layout

| Path | What it is |
|---|---|
| `sample/make-store-sales.py` | Seeded generator: sixty nights, 738,708 rows, three defective files, thirty load outcomes |
| `sql/`, `monitoring/`, `lib.sh` | The checks, the error budget, the metric, policy and lifecycle rule, and the helpers |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and 41 files of real output |
| `RUNBOOK.md`, `Session-14-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
