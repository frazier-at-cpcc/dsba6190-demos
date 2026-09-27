# Session 11 demonstration · Build a stream, then break it

This demonstration accompanies Session 11, Streaming. Crown Street Markets, the fictional 40-store
Charlotte grocery chain from the Session 6 demonstration, streams its register sales from Pub/Sub
through three Dataflow jobs into BigQuery. It then sends the jobs a late sale, a retried sale and a
malformed record, and drains one job while cancelling another.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough. The three streaming jobs bill for every minute they run,
so read its cost note before you start.

## Key results

| Step | Result | Capture |
|---|---|---|
| 2 | The jobs reported Running 111 s after submission and wrote their first rows at 250 s | `03`, `03b` |
| 3 | Both jobs counted 200 sales and $18,298.80 in one window | `04`, `05` |
| 5 | The baseline job dropped the CLT-031 sale of $412.18, rung 30 minutes earlier, and reported no error | `07`, `08` |
| 6 | The lateness job placed the same sale in its 15:14 window as pane 2, a late firing | `09` |
| 7 | One sale published twice counted as 2 sales and $176.80 in the baseline job, and as 1 sale and $88.40 in the dedup job | `10`, `11` |
| 8 | The `"$3.49"` record reached the dead-letter topic three times with its `ValueError`, and no job stopped | `12`, `13`, `14` |
| 10 | The baseline job reached Drained and the lateness job reached Cancelled within four minutes | `15`, `16` |
| 11 | The dedup job still reported Cancelling 60 s after the cancel, and no topic remained | `17`, `18` |

## Known issues and fixes

- All three jobs failed on the first launch. A freshly enabled Dataflow API started them before its
  service agent held its role. `live-setup.sh` and `capture.sh` now grant
  `roles/dataflow.serviceAgent` and wait 60 seconds before launching.
- Workers run without external IP addresses, so the subnet needs Private Google Access.
  `live-setup.sh` warns when it is off.
- A job reports Running before it can write. `live-setup.sh` publishes small warm-up bursts until
  the baseline table exists.
- One malformed record produces three dead letters, one from each job, because the jobs share one
  dead-letter topic.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `pipeline/register_stream.py` | The Beam pipeline, three variants selected by `--variant` |
| `pipeline/registers.py` | The register simulator: `burst`, `late`, `duplicate`, `malformed` |
| `live-setup.sh` | Creates the topics, launches the three jobs and waits for first rows. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 19 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
