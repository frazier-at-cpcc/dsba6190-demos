# Session 1 demonstration · One nightly job, three ways

This demonstration accompanies Session 1, Cloud Foundations. Queen City Trip Analytics, the
fictional South End analytics firm used across the course, runs one night's trip rollup three ways:
on a Compute Engine virtual machine, as a Cloud Run job, and as a BigQuery query. It then compares
what each platform asked the company to manage, how long each run took, and what each run billed.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 4 | `--location` is not an update flag. The storage class changes in place | `10`, `11` |
| 6 | The VM took 104 s from create to `TERMINATED` for 7 s of work, and its disk remains | `16`, `17`, `18` |
| 7 | The Cloud Run execution took 29 s for 3 s of work, and nothing remains | `21`, `22` |
| 8 | BigQuery billed 51 MB of a 135 MB file, with 0.1 s of slot time | `25` |
| 9 | All three platforms returned the same twelve rows | `26` |
| 10 | The runs cost $0.00194, $0.00116 and $0.00030 at list price | `27` |

## Known issues and fixes

- The comparison step once failed on a working directory whose path contained spaces. Step 9 now
  runs inside the working directory, so the path no longer matters.
- The VM boots on a standard persistent disk. The cost line in step 10 therefore prices the disk
  at $0.04 per GB-month.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `sample/make-trips.py` | Generates the seeded night of trips |
| `job/rollup.sh` | The rollup that the VM and Cloud Run both run |
| `live-setup.sh` | Stages the bucket and the file. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 31 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
