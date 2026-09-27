# Session 10 demonstration · Read a plan, find the skew

This demonstration accompanies Session 10, Distributed Processing. Queen City Trip Analytics, the
fictional South End analytics firm used across the course, bills its fleet customers by joining
30,000,000 trips to 5,001 accounts on Serverless for Apache Spark. One account, `WALKUP`, holds 60
per cent of the trips. The demonstration reads the physical plan, finds the straggler task, traces
it to the data, and runs the join four ways: skewed, broadcast, salted and with adaptive query
execution. It then runs the same join in BigQuery.

Every command was run end to end on 27 September 2026 on Serverless for Apache Spark runtime 2.2,
which ran Spark 3.5.3, and `capture/` holds the real output of each one. `stages.py` prints the
stage summary that the Spark UI shows, read from each batch's event log, so the demonstration needs
no history server. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | The data holds 30,000,000 trips in 242,555,519 bytes and 5,001 accounts in 27,972 bytes. The generate batch took 152 s | `01`, `02` |
| 3 | In the baseline join stage, the median task took 0.4 s and the slowest 16.9 s, a ratio of 43.5. One task read 206.2 MB | `05`, `16` |
| 4 | `WALKUP` holds 17,997,932 trips, a share of 0.5999 | `06` |
| 5 | Broadcast removed the join shuffle. The batch took 164 s against the baseline's 213 s | `03`, `07`, `08` |
| 6 | Salting cut the slowest join task to 3.1 s and the ratio to 8.8. The largest task read 7.8 MB, and the shuffle grew to 420.3 MB | `09`, `10`, `16` |
| 7 | Adaptive execution coalesced the join to 5 tasks with a ratio of 2.2, but it did not split the skewed partition. The straggler took 20.0 s | `11`, `12`, `16`, `17` |
| 8 | BigQuery used 1.4 slot-seconds and processed 686.7 MB in 4 stages | `13` |
| 9 | All four variants returned 48 rows and 1.14017810626E9 in revenue. The Spark applications ran 72.7 to 111.9 s inside batches of 164 to 213 s | `14`, `18` |

## Known issues and fixes

- Adaptive execution did not split the skewed partition. The `WALKUP` partition read 206.2 MB,
  which is below the default skew threshold of 256 MB. Step 7 shows this result.
- Serverless startup and shutdown took 86 to 101 seconds of every batch's wall clock, outside the
  Spark application itself.
- `stages.py` cannot read the zstd-compressed event logs the runtime writes by default. Every batch
  therefore sets `spark.eventLog.compress=false`.
- Each batch holds 12 vCPUs. Three batches that overlap need 36 vCPUs of your project's
  `CPUS_ALL_REGIONS` quota, so the `submit` helper waits for the previous batch to finish.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `jobs/billing.py`, `stages.py` | The PySpark job in five modes, and the event-log reader |
| `live-setup.sh`, `lib.sh` | The bucket, the generate batch, the BigQuery load, and the shell helpers. `live-setup.sh` creates resources and never deletes them |
| `capture.sh`, `capture/`, `plan/` | The recorder, its 18 output files, and the four physical plans |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
