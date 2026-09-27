# Session 10 live demo · read a plan, find the skew

The hour-long distributed-processing demonstration for Session 10, Distributed Processing, taught
Thursday 22 October 2026 on Zoom with the instructor off site. Queen City Trip Analytics, the
fictional South End firm from Sessions 7 and 8, bills its fleet customers by joining 30,000,000
trips to 5,001 accounts on Serverless for Apache Spark. One account, `WALKUP`, holds 60 per cent of
the trips. The hour reads the plan, finds the straggler, traces it to the data, and runs the join
four ways.

Captured on 27 September 2026 against project `YOUR_PROJECT_ID`, runtime 2.2 with Spark 3.5.3.
`live-setup.sh`, `lib.sh` and the notebooks were written from `capture.sh` afterwards and have not
yet run against the project. Run `prep.ipynb` and `demo.ipynb` once before 22 October.

## What the rehearsal changed

- **Adaptive execution did not split the skewed partition.** The plan called for showing
  `AQEShuffleRead` with coalesced and split partitions. The final plan shows coalescing only. The
  `WALKUP` partition read 206.2 MB, below the 256 MB default skew threshold, and its task ran
  20.0 seconds against the baseline's 16.9. Step 7 now teaches that result.
- **Serverless startup is about 90 seconds, not seconds.** Every batch spent 86 to 101 seconds of
  its wall clock outside the Spark application. The deck's startup figures now say so.
- **The event logs had to be uncompressed** for `stages.py` to read them, so every batch sets
  `spark.eventLog.compress=false`.
- **The Spark UI became a stage table.** `stages.py` prints the summary row the Spark UI shows, from
  the event log, so a Zoom session from off site depends on no history server.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 1 | 30,000,000 trips in 242,555,519 bytes; accounts 27,972 bytes; generate 152 s | `01`, `02` |
| 3 | Join stage: median 0.4 s, max 16.9 s, ratio 43.5, 377.8 MB; one task read 206.2 MB | `05`, `16` |
| 4 | `WALKUP` holds 17,997,932 trips, a share of 0.5999 | `06` |
| 5 | Broadcast removes the join shuffle; wall clock 164 s against 213 s | `03`, `07`, `08` |
| 6 | Salted: max 3.1 s, ratio 8.8, largest task 7.8 MB, shuffle 420.3 MB; 165 s | `09`, `10`, `16` |
| 7 | Adaptive execution: coalesced to 5 tasks, ratio 2.2, straggler 20.0 s, not split; 169 s | `11`, `12`, `16`, `17` |
| 8 | BigQuery: 1.4 slot-seconds, 686.7 MB processed, 4 stages | `13` |
| 9 | All four variants: 48 rows, revenue 1.14017810626E9; Spark ran 72.7 to 111.9 s | `14`, `18` |

## Layout

| Path | What it is |
|---|---|
| `jobs/billing.py`, `stages.py` | The PySpark job in five modes, and the event-log reader |
| `live-setup.sh`, `lib.sh` | Bucket, generate batch, BigQuery load, and the shell helpers. Applies; never destroys |
| `capture.sh`, `capture/`, `plan/` | The recorder, 18 files of real output, and the four physical plans |
| `RUNBOOK.md`, `Session-10-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
