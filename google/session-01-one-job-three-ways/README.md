# Session 1 live demo · one nightly job, three ways

The hour-long platform demonstration for Session 1, Cloud Foundations. Queen City Trip Analytics,
the fictional South End analytics firm used across the course, runs one night's trip rollup on a
Compute Engine VM, as a Cloud Run job, and as a BigQuery query, then compares what each one managed,
took and billed.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`. It replaces the
fifteen-minute Console walkthrough the session taught on 20 August.

## What the rehearsal changed

- **The comparison step failed on a path with spaces.** Step 9 now works inside the working
  directory.
- **The disk price assumed a balanced disk.** The VM boots on a standard persistent disk, so the
  cost line now uses $0.04 per GB-month.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 4 | `--location` is not an update flag; the storage class changes in place | `10`, `11` |
| 6 | 104 s from create to `TERMINATED` for 7 s of work; the disk remains | `16`, `17`, `18` |
| 7 | 29 s execution for 3 s of work; nothing remains | `21`, `22` |
| 8 | 51 MB billed of a 135 MB file, 0.1 s of slot time | `25` |
| 9 | Three platforms, twelve identical rows | `26` |
| 10 | $0.00194, $0.00116 and $0.00030 at list price | `27` |

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md`, `Session-01-Live-Demo-Runbook.pdf` | The instructor's runbook |
| `sample/make-trips.py` | The seeded night of trips |
| `job/rollup.sh` | The rollup the VM and Cloud Run both run |
| `live-setup.sh` | Stages the bucket and file. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and its 31 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
