# Session 7 demonstration · Make the cost visible, then govern it

This demonstration accompanies Session 7, Warehousing with BigQuery. Queen City Trip Analytics, the
fictional South End analytics firm used across the course, prices the queries behind its dashboards
against the New York City taxi data and builds a partitioned table. It then governs one month of the
same data as a lakehouse: an external table, a BigLake table, a policy tag and two row access
policies, queried as two different principals.

Every command was run end to end on 24 September 2026 with BigQuery CLI 2.1.38 and Google Cloud SDK
586.0.0, and `capture/` holds the real output of each one. A second full run from the notebooks on
27 September 2026 returned the captured figures, within a megabyte on the billed bytes of step 7.
Read `RUNBOOK.md` for the walkthrough. The demonstration uses no Terraform. Its artifacts are SQL
and a handful of `bq` and `gcloud` commands.

## Key results

| Step | Result | Capture |
|---|---|---|
| 2 and 4 | `SELECT *` and `SELECT * LIMIT 10` both process 6.97 GB | `03`, `06` |
| 3 | Three columns process 1.07 GB, and one column processes 0.54 GB | `04`, `05` |
| 5 | `COUNT(*)` over 36,256,539 rows bills 0 bytes | `07`, `08` |
| 6 | Two filters return identical rows for 1.07 GB and 46.61 GB, a factor of 43.5 | `09`, `10` |
| 7 | One week at JFK bills 997 MB unpartitioned and 17 MB partitioned, with the same answer | `16`, `17` |
| 8 | The plan shows 62 parallel inputs, 36,255,983 rows in, and 15,366 partial counts shuffled | `21` |
| 9 | The external table is estimated at 0 bytes and billed 45 MB | `25`, `26` |
| 10 | The analyst is denied the plain external table, allowed the BigLake table, and refused the tagged columns | `28`, `29`, `32` |
| 11 | The project owner sees 0 rows, then 2,463,900, and the analyst sees 1,716,028 | `36`, `38`, `39` |

The capture files label the project owner's queries `instructor`.

## Known issues and fixes

- An `EXPORT DATA` statement with no `ORDER BY` split one month of trips into 62 Parquet files, 59
  of them empty. `live-setup.sh` orders the export, which produces three files.
- A `GROUP BY` over zero rows returns no table at all. Step 11 counts with `COUNT(*)`, which always
  returns one row, so a zero is visible.
- The connection's service account is created asynchronously, and an immediate bucket grant once
  failed with "does not exist". `live-setup.sh` retries the grant for up to three minutes.
- The first impersonation grant on the second principal took about five minutes to propagate.
  `live-setup.sh` waits until that principal can run a query.
- A teardown with empty variables deletes every bucket in the project. Every destructive command
  therefore writes its names as `${NAME:?}`, which refuses to run when a name is empty.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `live-setup.sh` | Stages the dataset, the bucket and its Parquet, the connection, the taxonomy and the second principal. It creates resources and never deletes them |
| `lib.sh` | The four helpers `env.sh` loads: `dry`, `q`, `plan` and `as_analyst` |
| `sql/bytes-scanned.sql` | The cost queries for steps 1 to 6, ready to paste into the BigQuery editor |
| `capture.sh`, `capture/` | The recorder and its 47 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
