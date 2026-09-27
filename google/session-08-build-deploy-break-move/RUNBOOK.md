# Session 8 walkthrough · Build, deploy, break and move

This walkthrough builds one container image, runs it on Google Kubernetes Engine (GKE), updates it,
breaks it four ways, and moves it to Cloud Run, in eleven steps. The run used GKE Standard with
three `e2-medium` nodes in `us-central1-b`, Cloud Build, Artifact Registry and Cloud Run. Every
command below was run end to end on 27 September 2026, and `capture/` holds the full output of each
one. You can read the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost roughly $1 for about an hour: three `e2-medium` nodes, one
> load balancer, and a vulnerability scan on each pushed image. The GKE cluster is the costly part.
> Its nodes bill for every minute the cluster exists, whether or not anything runs on it. The GKE
> free tier covers the cluster management fee for one zonal cluster per billing account. Delete
> what you create, in the order step 11 shows, on the same day you create it.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional analytics company in South End, Charlotte, and the same
firm appears in the Session 7 demonstration. It is shipping its **fare-quote API**, which fleet
dispatch apps call all day and almost never at night. Each quote runs about 150 ms of model work,
and the team has never run Kubernetes.

The dispatcher loop, `loop.sh`, asks for a quote twice a second. The notebook runs it as a
background job. Each line of its output is one dispatcher's request, and each `ERR` line is a quote
that a dispatcher did not receive.

---

## Before you start

You need the gcloud CLI with its `kubectl` and `gke-gcloud-auth-plugin` components, Docker for step
1, and Jupyter with a Bash kernel.

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-08/env.sh
kubectl get nodes                        # three nodes, all Ready
```

The script enables five APIs and starts the cluster first, because cluster creation is the slow
part. While the cluster builds, the script builds the `v1` and `v2` images with Cloud Build. It then
waits for the cluster and pulls both images onto every node, so no pod waits on an image pull. It
deploys nothing. The whole script took **7 minutes 12 seconds** on the recorded run, so allow ten
minutes before you start `demo.ipynb`.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. The dispatcher loop runs in the background, and the `tail -6 loop.log` cells
show its latest lines, so you need no second terminal.

---

## The sequence

| # | Step |
|---|---|
| 1 | The Dockerfile, and the layer cache |
| 2 | Cloud Build, Artifact Registry, and the scan |
| 3 | Three replicas and a Service |
| 4 | Delete a pod |
| 5 | Scale out and in while the dispatcher asks |
| 6 | Roll out v2, then undo |
| 7 | Probes: none, wrong, right |
| 8 | Two limits, two failures |
| 9 | A disruption budget, then a node drain |
| 10 | The same image on Cloud Run |
| 11 | Teardown, in order |

### Step 1 · The Dockerfile, and the layer cache

`cat app/Dockerfile`, then `docker build` twice. The cold build spent **4.8 seconds** on the `pip
install` layer. After a one-line change to `main.py`, the rebuild reported `CACHED` for `WORKDIR`,
`COPY requirements.txt` and the `pip install`. **What to notice.** The Dockerfile copies the
dependency list before the source code. A change to the source therefore reuses the cached
dependency layer.

### Step 2 · Cloud Build, Artifact Registry, and the scan

`gcloud builds submit` runs the same Dockerfile in Cloud Build and pushes the image to Artifact
Registry. The vulnerability scan on `v2` reports **2 critical, 16 high and 27 medium** findings on a
current slim base image. **What to notice.** Scanning detects vulnerabilities. Binary Authorization
is the control that prevents an image from running.

### Step 3 · Three replicas and a Service

```sh
kubectl apply -f manifests/deployment-v1.yaml -f manifests/service.yaml
kubectl rollout status deployment/fare-api
```

The Deployment runs three pods, each with its own pod IP, behind one Service IP. The Service
received its external IP after 42 seconds and answered 73 seconds later. Each quote names the pod
that answered it. **What to notice.** Pods come and go, and the Service address stays fixed.

### Step 4 · Delete a pod

The replacement pod appeared **three seconds** later with a new name. **What to notice.** The
Deployment compares the desired state with the actual state and corrects the difference. Terraform
runs the same comparison once per apply, and Kubernetes runs it continuously.

### Step 5 · Scale out and in while the dispatcher asks

Start the loop, scale to six replicas, then scale back to three. The loop recorded **84 answered, 0
failed**. **What to notice.** Two mechanisms explain the zero. Readiness probes keep new pods out of
the Service until they can answer, and a ten-second `preStop` pause lets terminating pods finish
their requests.

### Step 6 · Roll out v2, then undo

The Deployment sets `maxSurge: 1, maxUnavailable: 0`. The loop's model column changes from `v1` to
`v2`, and back again after `kubectl rollout undo`. The loop recorded **105 answered, 0 failed**.
**What to notice.** A rolling update adds one new pod before it removes an old one, so capacity
never drops below three.

### Step 7 · Probes: none, wrong, right

| Variant | What happened | Dispatcher |
|---|---|---|
| No readiness probe, 25-second model load | New pods receive traffic before the server listens | **93 answered, 8 failed** |
| Probe on `/readyz`, which does not exist | The new pod stays `0/1` with `404` in its events, the rollout times out, and the old pods keep serving | **91 answered, 0 failed** |
| Probe on `/ready` | The probe hides the slow start, and the rollout completes | **131 answered, 0 failed** |

**What to notice.** A missing probe fails the callers. A wrong probe fails the deployment and
protects the callers.

### Step 8 · Two limits, two failures

A 64 MiB memory limit on a process that holds 256 MiB ends in `OOMKilled`, exit code 137, and a
restart loop. A 100m CPU limit stretches each quote to **1,500 ms instead of 150 ms**, and the pod
stays `Running` and Ready with no restarts and no event. **What to notice.** The memory failure is
loud. The CPU failure is quiet, and only a latency metric reveals it.

### Step 9 · A disruption budget, then a node drain

A budget of `minAvailable: 3` with three replicas allows no eviction, so the drain times out after
40 seconds. This setting blocks node upgrades. A budget of `minAvailable: 2` allows one disruption,
and the drain evicts one pod at a time and waits for its replacement. Uncordon the node afterwards.
**What to notice.** A disruption budget protects availability only when it leaves room for at least
one eviction.

### Step 10 · The same image on Cloud Run

```sh
time gcloud run deploy qc-fare-api --region "$REGION" --image "$IMAGE_BASE:v2" --allow-unauthenticated --quiet
```

The deployment took **9 seconds**. The first request took 0.88 s, and later requests took about 0.3
s. Cloud Run allows 80 concurrent requests per instance by default. **What to notice.** The
`--allow-unauthenticated` flag makes the service public so that any browser can call it. An internal
API should require authentication instead.

### Step 11 · Teardown, in order

```sh
kubectl delete service fare-api --wait=true && gcloud compute forwarding-rules list
kubectl delete deployment fare-api; kubectl delete pdb fare-api
gcloud container clusters delete "${CLUSTER:?}" --zone "${ZONE:?}" --quiet
gcloud run services delete qc-fare-api --region "${REGION:?}" --quiet
gcloud artifacts repositories delete "${REPO:?}" --location "${REGION:?}" --quiet
```

Delete the Service first, so its forwarding rule is released before the cluster goes. The cluster
took **236 seconds** to delete. Every name is written `${NAME:?}`, so an empty variable refuses to
run instead of deleting the wrong thing. The verification cell lists no clusters, Cloud Run
services, forwarding rules or repositories.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `gcloud builds submit` fails with `PERMISSION_DENIED` right after the API is enabled | A newly enabled Cloud Build API refuses builds for a few minutes. `live-setup.sh` retries six times at 45-second intervals |
| `kubectl` reports `gke-gcloud-auth-plugin not found` | The plugin sits in the SDK directory, which is not on `PATH`. Run `source ~/dsba6190-live-demo-08/env.sh`, which adds it |
| The Service's external IP answers nothing for a minute or two | The load balancer is programmed after the IP is assigned. Wait. The recorded run took 42 seconds for the IP and 73 more to answer |
| The loop prints only `ERR` right after step 3 | The load balancer is still being programmed. Wait a minute and start the loop again |
| A pod stays in `ImagePullBackOff` | The image path has a typo, or the nodes cannot read the repository. Compare the path in `manifests/` with `$IMAGE_BASE` |
| A rollout hangs longer than three minutes | Run `kubectl rollout undo deployment/fare-api` and compare your output with `capture/` |
| `gcloud run deploy` asks to enable an API | `live-setup.sh` was skipped or failed. Answer yes and wait a minute |
| The strict budget in step 9 holds the drain for 40 seconds | This is the expected result. Continue with `minAvailable: 2` |

---

## Files

| Path | What it is |
|---|---|
| `app/` | The fare-quote API: `main.py`, `requirements.txt` and the `Dockerfile` |
| `manifests/` | The Deployment variants, the Service and both budgets, with `IMAGE_BASE` placeholders |
| `loop.sh` | The dispatcher loop |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and the real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
