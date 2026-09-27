# Session 8 demonstration · Build, deploy, break and move

This demonstration accompanies Session 8, Containers and Kubernetes. Queen City Trip Analytics, the
fictional South End analytics firm used across the course, ships its fare-quote API to Google
Kubernetes Engine (GKE) and then to Cloud Run. A dispatcher loop asks for a quote twice a second
throughout, so every scale, rollout and failure shows up as answered or failed requests.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | The cold build spent 4.8 s on the dependency install. After a one-line change, the rebuild reported the install `CACHED` | `02`, `03` |
| 2 | The scan found 2 critical and 16 high findings on a current slim base image | `06` |
| 5, 6 | The loop recorded 84 and 105 quotes with zero failures through scaling and a rollout | `15`, `19` |
| 7 | With no probe, 8 of 101 quotes failed. With a wrong probe, the rollout stalled and none failed. With the right probe, 131 of 131 succeeded | `25`, `28`, `33` |
| 8 | A tight memory limit ended in `OOMKilled`, exit code 137. A 100m CPU limit stretched each quote from 150 ms to 1,500 ms while the pod stayed Ready | `38`, `40`, `41` |
| 10 | Cloud Run deployed the same image in 9 s. The first request took 0.88 s | `50`, `51` |
| 11 | Deleting the cluster took 236 s | `56` |

## Known issues and fixes

- Cloud Build can refuse the first build with `PERMISSION_DENIED` for a few minutes after its API is
  enabled. `live-setup.sh` retries the build six times at 45-second intervals.
- Terminating pods can stop serving before the load balancer removes them, which drops requests on
  every scale-in and rollout. Every `fare-api` Deployment in `manifests/` carries a ten-second
  `preStop` pause for this reason.
- The GKE authentication plugin installs into the Google Cloud SDK directory, which is not on
  `PATH`. The generated `env.sh` adds that directory to `PATH`.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `app/`, `manifests/`, `loop.sh` | The fare-quote API, the Kubernetes manifests, and the dispatcher loop |
| `live-setup.sh` | Builds both images, creates the cluster and pre-pulls the images. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 60 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
