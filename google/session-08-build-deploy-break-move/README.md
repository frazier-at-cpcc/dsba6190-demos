# Session 8 live demo · build, deploy, update, break, and move

The hour-long container demonstration for Session 8, Containers and Kubernetes, taught Thursday 8
October 2026. Queen City Trip Analytics, the fictional South End firm from Session 7, ships its
fare-quote API to GKE and then to Cloud Run while a dispatcher loop asks for quotes throughout.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`.

## What the rehearsal changed

- **Cloud Build refused the first build** with `PERMISSION_DENIED` minutes after its API was
  enabled. `live-setup.sh` now retries.
- **The first capture dropped requests on every scale-in and rollout**, even with correct readiness
  probes, because terminating pods stopped serving before the load balancer removed them. Every
  Deployment now carries a ten-second `preStop` pause. The re-capture shows zero failures except in
  the no-probe step, which is the contrast step 7 teaches.
- **The GKE auth plugin installs into the SDK directory, not onto `PATH`.** `env.sh` adds it.
- **The W08-G3 graphic was redrawn** in the same pass. It had placed GKE at low operational burden
  and managed endpoints at high, the reverse of the table on the same slide.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 1 | Dependency install 6.3 s cold, cached after a one-line change | `02`, `03` |
| 2 | 2 critical, 16 high findings on a current slim base | `06` |
| 5, 6 | 84 and 105 quotes, zero failed, through scaling and a rollout | `15`, `19` |
| 7 | No probe: 8 of 101 failed. Wrong probe: rollout stalls, 0 failed. Right probe: 0 of 131 | `25`, `28`, `33` |
| 8 | OOMKilled, exit 137. 1,500 ms per quote at 100m against 150 ms at 1 CPU, pod still Ready | `38`, `40`, `41` |
| 10 | Cloud Run deploy in 9 s; first request 0.88 s | `50`, `51` |
| 11 | Cluster deletion 236 s | `56` |

## Layout

| Path | What it is |
|---|---|
| `app/`, `manifests/`, `loop.sh` | The API, the Kubernetes manifests, the dispatcher loop |
| `live-setup.sh` | Builds both images, creates the cluster, pre-pulls. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and 60 files of real output |
| `RUNBOOK.md`, `Session-08-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
