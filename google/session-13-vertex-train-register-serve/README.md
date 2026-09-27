# Session 13 demonstration · Train, register and serve

This demonstration accompanies Session 13, Vertex AI. Queen City Trip Analytics, the fictional South
End analytics firm used across the course, trains two fuel-economy models on the UCI Auto MPG
dataset with Vertex AI custom training. It registers both as versions of one model, serves one from
an endpoint and the other as a batch prediction job, and prices three trips at $3.20 a gallon. It
then undeploys the endpoint to stop its hourly charge.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough. The endpoint bills for every hour a model stays deployed
on it, so read the cost note in the walkthrough before you start.

## Key results

| Step | Result | Capture |
|---|---|---|
| 2 | The ridge job took 5 min 40 s and the boosted-trees job 4 min 20 s, each on one `e2-standard-4`, for 392 rows | `01` |
| 3 | Test error was 2.52 mpg for ridge and 2.08 mpg for boosted trees, in artifacts of 2,209 and 182,117 bytes | `02`, `03` |
| 5 | Staging took 27 min 42 s, and deployment was most of it | `00` |
| 7 | Version 1 carries the aliases `ridge` and `default`, and version 2 carries `boosted` | `04`, `05` |
| 8 | Ridge predicted 13.7, 25.7 and 27.9 mpg, so fuel for 20 miles cost $4.67, $2.49 and $2.29 | `08`, `09` |
| 9 | The batch job succeeded after 1,141 s and wrote 392 predictions | `11`, `12` |
| 10 | After the undeploy, prediction failed with `FAILED_PRECONDITION` because `traffic_split` was not set | `13` to `15` |
| 11 | The endpoint and model lists both printed `Listed 0 items.` | `16`, `17` |

## Known issues and fixes

- A local Docker build failed. The `--local-package-path` option builds an image on your own
  machine. The trainer now ships as a source distribution that `live-setup.sh` builds itself, and
  it runs on the prebuilt `sklearn-cpu.1-6` training container with `python-module=trainer.train`.
- A pipeline that selected columns by name failed in the prediction container, which passes each
  instance as a plain list. The trainer selects columns by position.
- Paths with spaces broke `--json-request` and `curl -d @file`. `env.sh` now changes into
  `~/dsba6190-live-demo-13`, and every command names its files relatively.
- Deployment took about 21 minutes, and batch prediction took about 19. Step 7 submits the batch job
  right after version 2 is registered, and step 9 collects it.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `trainer/`, `setup.py` | The trainer package: a scikit-learn pipeline that selects columns by position |
| `sample/auto-mpg.data` | The UCI Auto MPG dataset, CC BY 4.0 |
| `live-setup.sh` | Trains both models, registers ridge and deploys it. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 18 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
