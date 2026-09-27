# Session 11 live demo · build a stream, then break it

The hour-long streaming demonstration for Session 11, Streaming Architectures, taught Thursday
29 October 2026. Crown Street Markets, the fictional 40-store Charlotte grocery chain from
Session 6, streams its register sales from Pub/Sub through three Dataflow jobs into BigQuery, then
sends them a late sale, a retried sale and a malformed record, and drains one job while cancelling
another.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`.

## What the rehearsal changed

- **All three jobs failed on the first launch** because the freshly enabled Dataflow API started
  them before its service agent held its role. `capture.sh` and `live-setup.sh` now create the
  service agent, grant `roles/dataflow.serviceAgent`, and wait 60 seconds.
- **Workers take no external IP.** Every launch passes `--no_use_public_ips`, which avoids the
  project's external IP address quota and requires Private Google Access on the subnet.
  `live-setup.sh` warns when it is off.
- **A job reports Running before it can write.** The jobs ran 111 seconds after submission and
  wrote first rows at 250. `live-setup.sh` blocks on both, publishing small warm-up bursts until the
  baseline table exists, and the deck's run sheet starts the jobs before class.
- **The duplicate step now retries a sale, not a message.** The planned step deduplicated on the
  Pub/Sub message ID, which two publishes never share. The register simulator publishes one
  `sale_id` twice, and the dedup job reads with `id_label="sale_id"`.
- **The late-sale query filters on the sale's own minute.** `capture.sh` filtered on windows older
  than 20 minutes, which in class would also catch the step 3 burst. The notebook filters on a
  two-minute band around the minute the sale was rung.
- **One malformed record produced three dead letters,** one from each job, because the jobs share a
  dead-letter topic. The deck says so rather than hiding it.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 2 | Jobs Running 111 s after submission, first rows at 250 s | `03`, `03b` |
| 3 | 200 sales and $18,298.80 in one window, in both jobs | `04`, `05` |
| 5 | The CLT-031 sale of $412.18, rung 30 minutes earlier: no rows in the baseline job | `07`, `08` |
| 6 | The same sale in the lateness job's 15:14 window, pane 2, a late firing | `09` |
| 7 | One sale published twice: baseline 2 sales and $176.80, dedup 1 and $88.40 | `10`, `11` |
| 8 | `"$3.49"` dead-lettered with its `ValueError`, three copies, no job stopped | `12`, `13`, `14` |
| 10 | Baseline Drained and lateness Cancelled within four minutes | `15`, `16` |
| 11 | Dedup still Cancelling 60 s after the cancel; no topics left | `17`, `18` |

## Layout

| Path | What it is |
|---|---|
| `pipeline/register_stream.py`, `pipeline/registers.py` | The Beam pipeline in three variants, and the register simulator |
| `live-setup.sh` | Creates the topics, launches the three jobs, waits for first rows. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and 19 files of real output |
| `RUNBOOK.md`, `Session-11-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
