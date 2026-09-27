# Session 13 live demo · train, register, and serve on Vertex AI

The hour-long Vertex AI demonstration for Session 13, Scalable ML and Deep Learning, taught Thursday
12 November 2026. Queen City Trip Analytics, the fictional South End firm from Sessions 7 and 8,
trains two fuel-economy models on the UCI Auto MPG dataset, registers both as versions of one model,
serves one from an endpoint and the other as a batch job, prices three trips at $3.20 a gallon, and
undeploys the endpoint in front of the room.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`. The notebooks were
generated from `capture.sh`'s commands and checked with `bash -n`; they have not yet been run end to
end against the project.

## What the rehearsal changed

- **A local Docker build failed on the instructor's Mac.** `--local-package-path` builds an image
  on the laptop. The trainer now ships as a source distribution that `live-setup.sh` builds itself,
  and it runs on the prebuilt `sklearn-cpu.1-6` training container with
  `python-module=trainer.train`.
- **A pipeline that selected columns by name failed in the prediction container**, which passes each
  instance as a plain list. The trainer now selects columns by position.
- **Paths with spaces broke `--json-request` and `curl -d @file`.** `env.sh` now changes into
  `~/dsba6190-live-demo-13`, and every command names its files relatively.
- **Batch prediction took 1,141 seconds, about 19 minutes.** The hour submits it at step 7, right
  after version 2 is registered, and collects it at the end of step 9.
- **Deployment took about 21 minutes** of the 27 minutes 42 seconds of staging, against the script's
  own estimate of ten. `live-setup.sh` deploys before class, and the endpoint bills from then until
  step 10.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 2 | Training jobs of 5 min 40 s for ridge and 4 min 20 s for boosted trees, each on one `e2-standard-4`, for 392 rows | `01` |
| 3 | Test error 2.52 mpg for ridge and 2.08 mpg for boosted trees; artifacts of 2,209 and 182,117 bytes | `02`, `03` |
| 5 | Staged in 27 min 42 s, most of it deployment | `00` |
| 7 | Version 1 `ridge,default`, version 2 `boosted` | `04`, `05` |
| 8 | 13.7, 25.7 and 27.9 mpg; fuel for 20 miles $4.67, $2.49 and $2.29 | `08`, `09` |
| 9 | Batch job succeeded after 1,141 s and wrote 392 predictions | `11`, `12` |
| 10 | After undeploy, `FAILED_PRECONDITION`: `traffic_split` not set | `13` to `15` |
| 11 | `Listed 0 items.` for endpoints and models | `16`, `17` |

## Layout

| Path | What it is |
|---|---|
| `trainer/`, `setup.py`, `sample/` | The trainer package and the UCI Auto MPG data, CC BY 4.0 |
| `live-setup.sh` | Trains both models, registers ridge, deploys it. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and 18 files of real output |
| `RUNBOOK.md`, `Session-13-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
