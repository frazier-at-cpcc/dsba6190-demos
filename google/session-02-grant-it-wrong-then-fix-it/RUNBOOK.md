# Session 2 live demo · runbook

Grant it wrong, then fix it. One hour, twelve steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: two BigQuery datasets,
one analyst service account, one custom-mode VPC, and one `e2-micro` VM in `us-east1-b`. Every
command below was run, and `capture/` holds the full output of each one.

**Do not run `capture.sh` in class.** It stages its own datasets and analyst and deletes everything
through an exit trap. `live-setup.sh` provisions and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it on your own account costs
> under $0.05: an `e2-micro` VM for about ten minutes and a few megabytes of BigQuery queries. IAM,
> firewall rules and Private Google Access carry no charge. **Destroy what you create, in the order
> step 12 shows.**

---

## The scenario · Crown Street Markets

**Crown Street Markets** is fictional: a 40-store Charlotte grocery chain that returns in Sessions
11 and 12. Tonight it gives its first analyst access to its first analytics project. The project
holds two datasets. `crown_curated_NNNNN.store_sales` holds one row per store per day and no
customer data. `crown_raw_NNNNN.loyalty_members` holds 5,000 loyalty members, each with a name, an
email and a card number. The analyst needs revenue by neighborhood and nothing else.

**The analyst is a service account.** A2 grants to groups, and the deck says why. Groups live in
Cloud Identity or Google Workspace under an organization, and the demo project sits under no
organization, so it has no groups. Say so in those words. A service account named
`cs-analyst-NNNNN`, displayed as "Crown Street analyst (stands in for the analysts group)", is the
nearest principal the instructor can act as. Every command prefixed `as_analyst` runs through
service account impersonation with the analyst's permissions and nothing more.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Identity is the perimeter | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · The network and the exfiltration path | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | A2 workshop, then Lab 2 | 25 |
| 2:55–3:00 | Wrap | 5 |

The access matrix and the limits slide moved out of the concept blocks into the A2 workshop. The
workshop opens on the analyst row that steps 5 and 11 grant and verify.

---

## Before class

```sh
cd "lectures/demos/session-02-grant-it-wrong-then-fix-it"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 15
source ~/dsba6190-live-demo-02/env.sh
bq ls | grep crown_                            # two datasets
```

The script enables four APIs, writes the seeded sample, loads both tables, copies `loyalty_members`
to `members_backup`, creates the analyst's service account, and grants the instructor
`roles/iam.serviceAccountTokenCreator` on it. It then waits until impersonation works. It grants the
analyst nothing. It took **126 seconds** on the rehearsal.

| Symptom | Cause | Fix |
|---|---|---|
| `bq add-iam-policy-binding` on the curated dataset fails with an allowlisting error | The `bq` command for dataset-level IAM is not available to this project | Step 5 grants `dataViewer` with BigQuery's SQL `GRANT ... ON SCHEMA`, which works and shows the level in the statement |
| The first `as_analyst` command fails with a permission error on token creation | A new token-creator grant takes a minute or two to reach IAM | `live-setup.sh` now polls `gcloud auth print-access-token --impersonate-service-account` until it succeeds. About 100 seconds of the 126 were this wait |
| Step 11 still reads card numbers after Editor was removed | Revocation propagates in minutes, not seconds. See step 11 | The notebook's wait loop polls every ten seconds until the raw table is refused. Never assume a revocation |
| The Editor binding at step 3 lists a `deleted:serviceAccount:` member | An earlier rehearsal deleted its analyst without removing the binding first | Harmless. Use it: step 12 removes bindings before the account for exactly this reason |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. Every command is a cell, and the two wait loops print how long they waited.

**The Console is optional.** At step 3 the instructor may make the Editor grant on **IAM and
Admin**, **IAM**, **Grant access** instead of the command line, and open the role picker to show
Basic roles listed above every predefined role. Slide 31 holds the 27 August screenshot of that
picker as a backup.

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | Two datasets, and what the analyst sees | 4 | 28 |
| 2 | How big each role is | 3 | 29 |
| 3 | Grant Editor on the project | 5 | 30, 31 |
| 4 | What Editor lets the analyst do | 6 | 32 |
| 5 | Fix it: two roles, each at its own level | 5 | 33 |
| 6 | Read the policy at both levels | 5 | 34 |
| 7 | The account nobody granted, and the key nobody holds | 4 | 35 |
| 8 | A private network, a VM, and no way in | 7 | 36 |
| 9 | One firewall rule, and still no way out | 5 | 37 |
| 10 | Private Google Access | 5 | 38 |
| 11 | After: the fix, verified | 7 | 39, 40 |
| 12 | Teardown, bindings before the account | 3 | 41 |

Slide 24 is the divider, slide 25 introduces the scenario, and slides 26 and 27 carry the run sheet.
Slide 31 is the Console role picker. Slides 42 to 44 are the A2 workshop and slide 45 is Lab 2. The
deck runs to 50 slides.

### Step 1 · Two datasets, and the analyst sees neither · 4 minutes

As the instructor, `bq ls` shows `crown_curated_26041` and `crown_raw_26041`. A three-row query on
the raw table returns names, emails and card numbers. As the analyst, the same listing returns **0
datasets**. **What to notice.** IAM denies everything no binding allows. Every grant from here on is
a decision.

### Step 2 · How big each role is · 3 minutes

`roles/editor` carries **12,135** permissions. `roles/bigquery.dataViewer` carries **23** and
`roles/bigquery.jobUser` carries **10**. **What to notice.** The two small roles are the analyst row
of the access matrix. Editor is the role the Console offers first.

### Step 3 · Grant it wrong · 5 minutes

```sh
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/editor --condition=None --quiet
```

The grant took effect in **3 seconds**. The binding lists four members, and the first is
`deleted:serviceAccount:cs-analyst-25186@...`, an earlier rehearsal's analyst whose binding outlived
it. **What to notice.** Remember the three seconds; step 11 needs it. Show the Console picker here
if the room wants it.

### Step 4 · What Editor lets the analyst do · 6 minutes

As the analyst, three commands succeed. The analyst reads card numbers. It deletes `members_backup`
with no prompt, and the instructor's listing confirms the table is gone. It lists every VM in the
project, **four** in the rehearsal, belonging to other sessions' demonstrations. **What to notice.**
Nobody broke in. This is the breach from the opening slide: a valid grant that is far too broad.

### Step 5 · Fix it · 5 minutes

```sh
gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/editor --condition=None --quiet
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/bigquery.jobUser --condition=None --quiet
q "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$PROJECT.$CURATED\` TO 'serviceAccount:$ANALYST'"
```

`jobUser` on the project, because every query is a job and jobs run in a project. `dataViewer` on
the curated dataset only. The raw dataset receives nothing. **Say plainly** that the analyst can
still read card numbers for several minutes, and that steps 6 to 10 fill that time on purpose.

### Step 6 · Read the policy at both levels · 5 minutes

The project policy, filtered to the analyst, shows `roles/bigquery.jobUser` only. The curated
dataset's access list shows the analyst as `READER`, beside `projectWriters`, `projectOwners` and
`projectReaders`. **What to notice.** `projectWriters` is how step 4's delete worked: every project
Editor is a writer on every dataset. An audit reads every level. This JSON is the artifact Terraform
manages in Session 3.

### Step 7 · The account nobody granted, and the key nobody holds · 4 minutes

The default Compute Engine service account holds `roles/editor`. Nobody typed that grant: enabling
the Compute Engine API made it, because the project has no organization policy to block it. It also
holds `roles/datafusion.serviceAgent` from other work in the project. The analyst's key list shows
one key, `SYSTEM_MANAGED`. **What to notice.** Impersonation issued short-lived tokens all hour. No
key file exists to leak.

### Step 8 · A private network, a VM, and no way in · 7 minutes

```sh
gcloud compute networks create "$NET" --subnet-mode custom
gcloud compute networks subnets create "$SUBNET" --network "$NET" --region "$REGION" --range 10.20.0.0/24
gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-micro --subnet "$SUBNET" --no-address ...
gcloud compute firewall-rules list --filter="network:$NET"
time timeout 60 gcloud compute ssh "$VM" --zone "$ZONE" --tunnel-through-iap ...
```

Custom mode, one subnet at `10.20.0.0/24` with Private Google Access off, a VM at `10.20.0.2` with
no external IP, and no firewall rules. SSH through Identity-Aware Proxy hung and **gave up after 21
seconds**. **What to notice.** The implied deny-ingress rule drops the packet silently. The failure
is a timeout, not an error, exactly as the Hour 2 slide predicted.

### Step 9 · One firewall rule, and still no way out · 5 minutes

```sh
gcloud compute firewall-rules create "$FW" --network "$NET" --direction INGRESS --allow tcp:22 \
  --source-ranges 35.235.240.0/20
```

`35.235.240.0/20` is IAP's range, so SSH arrives only through Google's authenticated tunnel. SSH now
works and runs `probe.sh`. `storage.googleapis.com`, `bigquery.googleapis.com` and `example.com` all
report **no route (timed out)**. **What to notice.** Egress is allowed, but a VM with no external IP
and no Cloud NAT reaches nothing outside its network, Google's own APIs included.

### Step 10 · Private Google Access · 5 minutes

```sh
gcloud compute networks subnets update "$SUBNET" --region "$REGION" --enable-private-ip-google-access
```

The same probe: Cloud Storage **400**, BigQuery **404**, `example.com` still **no route**. **What to
notice.** A 400 and a 404 are replies from the API front end to a bare URL, and a reply is the
point. The setting is on the subnet. Nothing on the VM changed.

### Step 11 · After: the fix, verified · 7 minutes

**This is the propagation lesson, and it is the reason the fix goes in at step 5.** A grant took
effect in 3 seconds at step 3. A revocation takes minutes. Google documents that access changes
typically take about two minutes and sometimes seven or longer. The rehearsals landed across that
range.

| Run | Raw table still readable after Editor was removed |
|---|---|
| Rehearsal | 84 seconds |
| Rehearsal | More than seven minutes. That capture reached step 11 and recorded Editor still in effect |
| Final capture, 27 September | About five minutes. The step 11 wait added **132 s** after the network steps |

The final-capture figure comes from the BigQuery job timestamps: the step 5 `GRANT` job started at
12:23:12 and the refused card-number query at step 11 ran at 12:28:28.

Run the wait cell first. It polls the raw table as the analyst every ten seconds and prints how long
it waited. Then, as the analyst:

- Revenue by neighborhood from the curated dataset succeeds. Uptown leads with **113,812** baskets
  and **$5,180,842** across 28 days.
- The card-number query is refused: `Access Denied ... User does not have permission to query
  table`.
- `bq rm` on `store_sales` is refused: `Permission bigquery.tables.delete denied`.
- `gcloud compute instances list` is refused: `Required 'compute.instances.list' permission`.

**What to notice.** Access being added is visible at once to the person waiting for it. Access being
removed is visible to nobody, so a revocation needs a test, not an assumption. **If the wait passes
seven minutes,** say so, show slides 39 and 40, and move to step 12. The delay is the lesson, not a
failure.

### Step 12 · Teardown, bindings before the account · 3 minutes

```sh
gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet
gcloud compute firewall-rules delete "${FW:?}" --quiet
gcloud compute networks subnets delete "${SUBNET:?}" --region "${REGION:?}" --quiet
gcloud compute networks delete "${NET:?}" --quiet
gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:${ANALYST:?}" \
  --role roles/bigquery.jobUser --condition=None --quiet
gcloud iam service-accounts delete "${ANALYST:?}" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${CURATED:?}"
bq --project_id="$PROJECT" rm -r -f -d "${RAW:?}"
```

The VM first, because a subnet that holds an instance cannot be deleted. The binding before the
account, or the policy keeps a `deleted:` member like the one at step 3. Every name is written
`${NAME:?}` so an empty variable refuses to run. The verification found no network and no `crown_`
datasets, but the service account listing still returned the analyst seconds after the delete
returned. **Run the listing again before leaving the room.** The rehearsal did not record a second
listing.

---

## If it fails live

| What happened | Do this |
|---|---|
| `as_analyst` fails with a token-creation error | `live-setup.sh` waits for impersonation, so this should not happen. Wait a minute and rerun the cell |
| Step 3's wait loop runs longer than a minute | Grants usually land in seconds. Keep talking about what Editor includes and let it finish |
| SSH at step 9 still times out | The rule takes a few seconds to apply. Wait fifteen seconds and rerun. Check that `--source-ranges` is `35.235.240.0/20` |
| The probe at step 10 still reports no route | Private Google Access takes a few seconds to apply. Wait twenty seconds and rerun the probe |
| Step 11's wait passes seven minutes | Present slides 39 and 40 and teach the delay. Rerun the three refusals after step 12's VM deletion, before deleting the account |
| The hour runs short | Shorten step 2 and step 7. Never skip step 11's wait or step 12 |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-crown.py` | Seeded generator for `store_sales.csv` and `loyalty_members.csv` |
| `lib.sh` | Shell helpers: `q` runs a query and prints bytes billed, `as_analyst` impersonates the analyst |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and 34 files of real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
| `RUNBOOK.md`, `build-runbook-pdf.py`, `Session-02-Live-Demo-Runbook.pdf` | This document and its podium PDF |
