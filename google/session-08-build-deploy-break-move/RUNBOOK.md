# Session 8 live demo · runbook

Build, deploy, update, break, and move. One hour, eleven steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: GKE Standard,
three `e2-medium` nodes in `us-central1-b`, Cloud Build, Artifact Registry, Cloud Run. Every
command below was run, and `capture/` holds the full output of each one.

**Do not run `capture.sh` in class.** It stages its own cluster and deletes everything through an
exit trap. `live-setup.sh` provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it on your own account costs
> roughly $1 for an hour: three `e2-medium` nodes, one load balancer, and a vulnerability scan per
> pushed image. GKE's free tier covers the management fee of one zonal cluster. **Destroy what you
> create, in the order step 11 shows.**

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is fictional: the South End analytics firm from Session 7. Tonight it
ships its **fare-quote API**, which fleet dispatch apps call all day and almost never at night. Each
quote runs about 150 ms of model work, and the team has never run Kubernetes. That is A8's workload
on purpose, so the hour is evidence students can cite.

The dispatcher loop (`loop.sh`, run as a background job by the notebook) asks for a quote twice a
second. Each line is a dispatcher's request; each `ERR` is a quote a dispatcher did not get.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up and announcements | 10 |
| 0:10–0:55 | Concept Block 1 · Containers | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Choosing a platform | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | A8 workshop while the cluster builds, then Lab 8 | 25 |
| 2:55–3:00 | Wrap | 5 |

---

## Before class

```sh
cd "lectures/demos/session-08-build-deploy-break-move"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 45
source ~/dsba6190-live-demo-08/env.sh
kubectl get nodes                              # three Ready
```

The script enables five APIs, starts the cluster, builds `v1` and `v2` with Cloud Build, waits for
the cluster, and pulls both images onto every node so no pod waits on an image pull. It deploys
nothing. It took **7 minutes 12 seconds** on the rehearsal.

| Symptom | Cause | Fix |
|---|---|---|
| `gcloud builds submit` fails with `PERMISSION_DENIED` right after the API is enabled | A freshly enabled Cloud Build API refuses builds for a few minutes | The script retries six times at 45-second intervals |
| `kubectl` says `gke-gcloud-auth-plugin not found` | The plugin sits in the SDK directory, not on `PATH` | `env.sh` adds the SDK's `bin` directory to `PATH` |
| The Service's external IP answers nothing for a minute or two | The load balancer is programmed after the IP is assigned | Wait. The rehearsal took 42 seconds for the IP and 73 more to answer |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. The dispatcher loop runs in the background and the `tail -6 loop.log` cells
show it, so no second terminal is needed.

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | The Dockerfile, and the layer cache | 4 | 32 |
| 2 | Cloud Build, Artifact Registry, and the scan | 5 | 33 |
| 3 | Three replicas and a Service | 6 | 34 |
| 4 | Delete a pod | 4 | 35 |
| 5 | Scale out and in while the dispatcher asks | 5 | 36 |
| 6 | Roll out v2, then undo | 6 | 37 |
| 7 | Probes: none, wrong, right | 9 | 38 |
| 8 | Two limits, two failures | 6 | 39 |
| 9 | A disruption budget, then a node drain | 6 | 40 |
| 10 | The same image on Cloud Run | 5 | 41 |
| 11 | Teardown, in order | 3 | 42 |

Slide 28 is the divider, slide 29 introduces the scenario, and slides 30 and 31 carry the run
sheet. The deck runs to 56 slides.

### Step 1 · The layer cache · 4 minutes

Change one line of `main.py` and rebuild. `WORKDIR`, `COPY requirements.txt` and the `pip install`
report `CACHED`; only the source copy runs. The cold install took 6.3 seconds. **What to notice.**
Dependencies before source is the whole rule.

### Step 2 · Built, pushed, scanned · 5 minutes

`gcloud builds submit` runs the same Dockerfile in Cloud Build and pushes to Artifact Registry. The
scan on `v2` reports **2 critical, 16 high, 27 medium** findings on a current slim base. **What to
notice.** Scanning detects. Binary Authorization is what prevents an image from running.

### Step 3 · Three replicas and a Service · 6 minutes

```sh
kubectl apply -f manifests/deployment-v1.yaml -f manifests/service.yaml
kubectl rollout status deployment/fare-api
```

Three pods, three pod IPs, one Service IP. Each quote names the pod that answered it.

### Step 4 · Delete a pod · 4 minutes

The replacement appeared **three seconds** later with a new name. Reconciliation, and the Terraform
loop from Week 3 run continuously.

### Step 5 · Scale while the dispatcher asks · 5 minutes

Start the loop, scale to six, then back to three. **84 answered, 0 failed.** Name the two reasons:
readiness probes gate new pods, and a ten-second `preStop` pause lets terminating pods finish.

### Step 6 · Roll out v2, then undo · 6 minutes

`maxSurge: 1, maxUnavailable: 0`. The loop's model column changes from `v1` to `v2` and back after
`kubectl rollout undo`. **105 answered, 0 failed.**

### Step 7 · Probes: none, wrong, right · 9 minutes

| Variant | What happened | Dispatcher |
|---|---|---|
| No readiness probe, 25-second model load | New pods get traffic before the server listens | **93 answered, 8 failed** |
| Probe on `/readyz`, which does not exist | New pod stays `0/1`, `404` in events, rollout times out, old pods keep serving | **91 answered, 0 failed** |
| Probe on `/ready` | The slow start is hidden; the rollout completes | **131 answered, 0 failed** |

**What to notice.** A missing probe fails the callers. A wrong probe fails the deploy and protects
them. That distinction is the highest-value minute of the hour.

### Step 8 · Two limits, two failures · 6 minutes

A 64 MiB memory limit on a process holding 256 MiB: `OOMKilled`, exit code 137, restarting. A 100m
CPU limit: each quote takes **1,500 ms instead of 150**, and the pod is `Running`, Ready, with no
restarts and no event. **What to notice.** The quiet failure can only be found in a latency metric.

### Step 9 · The budget refuses the drain · 6 minutes

`minAvailable: 3` with three replicas: the drain times out, because no eviction is ever allowed. That
is the anti-pattern that blocks node upgrades. `minAvailable: 2`: one disruption allowed, the drain
evicts one pod at a time and waits for its replacement. Uncordon the node afterwards.

### Step 10 · The same image on Cloud Run · 5 minutes

```sh
time gcloud run deploy qc-fare-api --region "$REGION" --image "$IMAGE_BASE:v2" --allow-unauthenticated --quiet
```

**9 seconds.** First request 0.88 s, later ones about 0.3 s. Concurrency 80 per instance by
default. **Say plainly** that `--allow-unauthenticated` is for the room's laptops, and that A8's
internal API must not use it.

### Step 11 · Teardown, in order · 3 minutes

```sh
kubectl delete service fare-api --wait=true && gcloud compute forwarding-rules list
kubectl delete deployment fare-api; kubectl delete pdb fare-api
gcloud container clusters delete "${CLUSTER:?}" --zone "${ZONE:?}" --quiet
gcloud run services delete qc-fare-api --region "${REGION:?}" --quiet
gcloud artifacts repositories delete "${REPO:?}" --location "${REGION:?}" --quiet
```

The Service first, so its forwarding rule is released before the cluster goes. The cluster took
**236 seconds** to delete. Every name is written `${NAME:?}` so an empty variable refuses to run.

---

## If it fails live

| What happened | Do this |
|---|---|
| A pod stays `ImagePullBackOff` | A registry path typo or a missing node IAM grant. The script pre-pulls both images, so this should not happen in class; present the capture slide |
| The loop prints only `ERR` right after step 3 | The load balancer is still being programmed. Wait a minute |
| A rollout hangs longer than three minutes | `kubectl rollout undo`, then present the capture slide |
| Cloud Run deploy asks to enable an API | `live-setup.sh` enables `run.googleapis.com`; answer yes and wait |
| The hour runs short | Skip step 9's strict budget and go straight to `minAvailable: 2`. Never skip step 11 |

---

## Files

| Path | What it is |
|---|---|
| `app/` | The fare-quote API: `main.py`, `requirements.txt`, `Dockerfile` |
| `manifests/` | The Deployment variants, the Service, and both budgets, with `IMAGE_BASE` placeholders |
| `loop.sh` | The dispatcher loop |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
