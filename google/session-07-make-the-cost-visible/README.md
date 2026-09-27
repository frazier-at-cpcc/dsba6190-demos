# Session 7 live demo · make the cost visible, then govern it

The hour-long demonstration for Session 7, Warehouses and Lakehouses, taught Thursday 1 October 2026.
The first half prices queries against the New York City taxi data and builds a partitioned table
live. The second half governs one month of the same data as a lakehouse: an external table, a BigLake
table, a policy tag and two row access policies, queried as two different principals.

The hour is framed as one company's work. **Queen City Trip Analytics** is a fictional
twelve-person analytics company in South End, Charlotte, that sells demand and pricing dashboards to
ground-transportation fleets and uses New York's public trip data as its benchmark market. Its
airport product stands behind step 7, and its first fleet customer's analyst is the second principal
in steps 10 and 11. `RUNBOOK.md` carries the full mapping.

Rehearsed and captured on 24 September 2026 against project `YOUR_PROJECT_ID`, BigQuery CLI
2.1.38 and Google Cloud SDK 586.0.0. There is no Terraform in this demonstration. The artifacts are
SQL and a handful of `bq` and `gcloud` commands.

## Why this demonstration is an hour

| Gap between Lab 7 and what A7 grades | Step that closes it |
|---|---|
| A7 Part B asks students to measure bytes scanned, and the two mistakes they make most are guessing instead of pricing and trusting `LIMIT` | 1 and 4 |
| Column pruning and table pruning, which are a third of A7's marks | 2, 3 and 6 |
| Partitioning and clustering appear in the lecture, and the lab never measures them | 7 |
| The Dremel execution model is drawn in Hour 1 and never observed | 8 |
| External tables versus BigLake tables, which is A7's central comparison | 9 and 10 |
| Policy tags and row access policies, which the lab never exercises | 10 and 11 |

## What the rehearsal changed

- **The Parquet export split into 62 files, 59 of them empty,** when exported without an order. An
  `ORDER BY` in the `EXPORT DATA` statement produces three files. Step 9 lists them, and 62 files of
  1.7 KB each is a distraction the room does not need.
- **Row access policies make a zero-row result print nothing.** A `GROUP BY` over no rows returns no
  table at all. The step 11 query therefore uses `COUNT(*)`, which always returns one row, so the
  owner's zero is visible.
- **The connection's service account is created asynchronously.** Granting it bucket access
  immediately after `bq mk --connection` failed once with "does not exist". `live-setup.sh` retries
  for up to three minutes.
- **The first impersonation grant took about five minutes to propagate.** `live-setup.sh` blocks
  until the second principal can run a query. The principal is kept between runs so later setups
  are ready in seconds.
- **A teardown with empty names deleted every bucket in the project.** During the notebook test, a
  failed `live-setup.sh` left `env.sh` unwritten, and the teardown cell ran with `$BUCKET` empty.
  `gcloud storage rm -r gs://` then deleted seven unrelated buckets. All seven were restored from
  soft delete within minutes. None held a live object; the noncurrent Terraform state history in
  three of them remains in soft delete until 1 October 2026. Every destructive command in both notebooks and the runbook now uses
  `${NAME:?}`, which refuses to run with an empty name, and the first cell of each notebook reports
  plainly when nothing is staged.

## Layout

| Path | What it is |
|---|---|
| `live-setup.sh` | Provisions the dataset, the bucket and its Parquet, the connection, the taxonomy and the second principal. **Applies. Never destroys** |
| `lib.sh` | The four helpers `env.sh` loads: `dry`, `q`, `plan`, `as_analyst` |
| `sql/bytes-scanned.sql` | The eight cost queries, ready to paste into the BigQuery editor |
| `capture.sh` | The headless recorder. Stages with `live-setup.sh`, runs all twelve steps, tears down through an exit trap |
| `capture/` | Full real output, one file per command, 47 files |
| `RUNBOOK.md` | The instructor document |
| `build-runbook-pdf.py` | WeasyPrint, Charlotte brand, podium sizing |
| `Session-07-Live-Demo-Runbook.pdf` | The runbook, built |
| `prep.ipynb`, `demo.ipynb` | Bash notebooks, commands only. `prep` is T minus 45 to T minus 35; `demo` is steps 1 to 12 with the teardown. Needs the Bash kernel |
| `build-notebook.py` | Regenerates both notebooks. Edit the generator, not the notebooks |

## Full run, 27 September 2026

`prep.ipynb` then `demo.ipynb`, executed end to end on the Bash kernel: 90 seconds and 153 seconds.
Every step returned the captured figures, within a megabyte on step 7's billed bytes, and the
teardown cell verified four zeros.

## Re-capture

```sh
./capture.sh YOUR_PROJECT_ID
```

About four minutes and under ten cents. It leaves one thing behind on purpose: the
`dsba6190-analyst` service account and its two grants. After a re-capture, the numbers in the deck's
capture slides, the runbook and the lecture must be checked against the new files, because the
suffix changes and the policy-tag name in step 10's error changes with it.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 2 and 4 | `SELECT *` and `SELECT * LIMIT 10` both 6.97 GB | `03`, `06` |
| 3 | Three columns 1.07 GB, one column 0.54 GB | `04`, `05` |
| 5 | `COUNT(*)` over 36,256,539 rows bills 0 bytes | `07`, `08` |
| 6 | 1.07 GB against 46.61 GB for identical rows, 43.5 times | `09`, `10` |
| 7 | One week at JFK bills 997 MB unpartitioned and 17 MB partitioned, same answer | `16`, `17` |
| 8 | 62 parallel inputs, 36,255,983 rows in, 15,366 partial counts shuffled | `21` |
| 9 | External table estimated at 0 bytes, billed 45 MB | `25`, `26` |
| 10 | Plain external table denied to the analyst, BigLake table allowed, tagged columns refused | `28`, `29`, `32` |
| 11 | The owner sees 0 rows, then 2,463,900; the analyst sees 1,716,028 | `36`, `38`, `39` |
