# Session 4 CI/CD demo · runbook

The infrastructure pipeline, worked. Twenty-three minutes, seven steps. A companion to the hour-long
Session 4 demonstration, and the worked example for the approval-control and drift-detection
sections of Assignment A4.

Rehearsed end to end on 10 September 2026 against project `YOUR_PROJECT_ID` and the repository
`frazier-at-cpcc/dsba6190-infrastructure-pipeline`, Terraform v1.5.7, `hashicorp/google` v5.45.2,
Conftest v0.69.0, `google-github-actions/auth` v3, `hashicorp/setup-terraform` v4.0.1. Every command
below was run; every expected output below is real, and the pull requests and the issue it produced
are still on GitHub as numbers 1 to 4.

**Do not run `capture.sh` in class.** It is the headless recorder. It approves its own deployments
through the API, closes its own pull requests, and destroys both buckets through an exit trap.
`live-setup.sh` is its opposite.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you want to reproduce it on your own
> GitHub account and Google Cloud account, it costs **under $0.01**, which Google's $300 free credit
> for a new account covers many times over. GitHub Actions minutes are free on a public repository.
> Opening a Google Cloud account requires a credit card at signup, though Google does not charge it.
> That is your choice and no part of this course requires it.
> **Destroy what you create.** The teardown step is the last step for a reason.

The figure covers three Cloud Storage buckets holding kilobytes for the length of a class, and seven
GitHub Actions runs totalling under three minutes of runner time. The state bucket, the service
account, and the federation remain between runs and cost nothing measurable.

---

## What the room sees, and where it comes from

| Stage | Slide | What happens | Where the room reads it |
|---|---|---|---|
| 1 | 20 | `fmt -check`, `init`, `validate` | The check on the pull request |
| 2 | 20 | `plan`, posted on the pull request | The sticky comment on the pull request |
| 3 | 23 | Conftest rejects the plan, and says why | The same comment, marked FAILED |
| 4 | 21 | A required reviewer opens the gate | Actions, the run page, **Review deployments** |
| 5 | 21 | `apply`, by a service account through federation | The apply job log |
| 6 | 21 | A scheduled `plan -detailed-exitcode` | An issue labelled `drift` |

Slide numbers are the numbers printed on the footer of the 57-slide Session 4 deck. Verify them once
against the built PDF before class; the deck builder inserts an agenda slide that heading counts
miss.

The pipeline is real GitHub Actions, which means every run takes between fifteen and fifty seconds
on a hosted runner. Each step below says what to say while the runner works. Do not fill that time
with silence and do not fill it by reading the workflow file.

---

## Before class

Drive the hour from `demo.ipynb` on the Bash kernel: VS Code, Select Kernel, Jupyter Kernel, Bash.

### T minus 30 minutes

```sh
cd lectures/demos/session-04-cicd-pipeline
./live-setup.sh YOUR_PROJECT_ID frazier-at-cpcc/dsba6190-infrastructure-pipeline
```

It applies the two buckets with your own credentials so the room starts from existing
infrastructure, resets `main` to `repo/`, pushes three branches ready to become pull requests,
enables the scheduled drift workflow, and closes any drift issue left from a rehearsal. A bucket
that exists but is missing from state is imported before the apply. The reset commit carries `[skip
ci]`, so no apply run waits at the gate before class. The first approval the room sees is the one it
just read.

In `demo.ipynb`, every cell that waits on GitHub Actions is a bounded loop. It returns when the run
completes and prints the run's conclusion and address. When the apply run reaches the gate, the cell
prints the browser instruction once and keeps waiting for your click. A cell that waits longer than
fifteen minutes stops and says so.

### T minus 25 minutes, verify

```sh
gh run list --repo frazier-at-cpcc/dsba6190-infrastructure-pipeline --limit 3
gcloud storage ls --project YOUR_PROJECT_ID | grep cicd
```

Expect no run in progress, and three buckets: `cicd-lake`, `cicd-scratch`, `tfstate-cicd`.

| Symptom | Cause | Fix |
|---|---|---|
| `Unable to acquire impersonated credentials` in a run log | The federation condition names a different repository | `./bootstrap.sh` again with the right `OWNER/REPO`; it updates the condition |
| `403 ... storage.buckets.create` in the plan job | The service account lost Storage Admin | `./bootstrap.sh` again; the binding is idempotent |
| The apply job runs without stopping at **Review deployments** | The `production` environment has no reviewer. Required reviewers need a public repository or a paid plan | Keep the repository public; re-run `./bootstrap.sh` |
| No plan comment appears on the pull request | The pull request came from a fork, which gets no `id-token` and no `pull-requests: write` | Open pull requests from branches in this repository |
| `Error acquiring the state lock` | A previous run is still applying, or a local terminal holds the lock | Wait for the run; `terraform force-unlock` only if the holder is dead |
| A check named CodeRabbit appears | An app installed on the account reviews public repositories | Ignore it, or uninstall it from the account settings |
| The drift run fails with `label not found` | The `drift` label is missing | `gh label create drift --repo OWNER/REPO` |
| `live-setup.sh` prints `exists but is not in state. Importing it.` | The state file lost the buckets and the buckets survived. The state for this demo was found empty on 27 September with both buckets still present | Nothing. The script adopts both buckets before it applies. Without the import, the apply fails with `409` |
| `live-setup.sh` stops with `! [rejected] demo/... (non-fast-forward)` | An older copy of `live-setup.sh` deleted the three branches in one push, which fails as a whole when one branch is already gone | Use the current script. It deletes each branch in its own push |
| A pull-request check sits in **Queued** and never starts | An apply run is waiting at the gate. It holds the `terraform-state` concurrency group, and every pull-request run queues behind it | Approve or reject that run under Actions. The current `live-setup.sh` pushes its reset with `[skip ci]` and creates no such run |
| An open `drift` issue appears the morning after class | The daily drift plan ran against the destroyed buckets and reported them as missing | The after-class cells disable the drift workflow. `live-setup.sh` enables it again |
| A notebook cell prints `No ... run after 120 s` | GitHub did not create the run, often because the push or dispatch failed | Read the cell's earlier output, then the Actions tab. Rerun the cell once the run exists |

### Set up the room

- Terminal at a size the back row can read, in `~/dsba6190-live-demo-04-cicd`.
- Four browser tabs, in this order: the repository's **Pull requests**, **Actions**,
  **Issues** filtered to `label:drift`, and the Cloud Console's **Cloud Storage** browser for the
  demo project.
- Deck on slide 20.

**Network contingency.** Pull requests 1, 2 and 3 and issue 4 are the rehearsal's own artifacts and
are still on GitHub. If a live run cannot start, open those instead and say plainly that they are
from the rehearsal on 10 September. The plain-text captures are in `capture/`.

---

## The sequence

Every command runs from `~/dsba6190-live-demo-04-cicd`. The three demo branches already exist on
GitHub, so no step involves editing HCL in front of the room.

### Step 1 · The repository, and who it trusts · slide 21 · 3 minutes

Open the repository README in the browser. Read the six-row table aloud; it is the lecture's list.

Then, in the terminal:

```sh
gh variable list
gcloud iam workload-identity-pools providers describe github \
  --workload-identity-pool github-actions --location global \
  --format "value(attributeCondition)"
```

Expect four variables, none of them a secret, and one line:

```
assertion.repository == 'frazier-at-cpcc/dsba6190-infrastructure-pipeline'
```

**What to notice.** There is no key. GitHub presents a signed token that names the repository;
Google Cloud trusts that token for this one repository and hands back a token that lasts an hour.
Stage 5 runs as `github-actions-tf`, and nobody can download its credentials because it has none.
Say that this is the whole answer to A4's secrets question for the pipeline itself, and that the
application's own secrets are a separate question the hour-long demo answers.

### Step 2 · A compliant pull request · slide 20 · 4 minutes

```sh
gh pr create --base main --head demo/label-cost-center --fill --web
```

The browser opens on the new pull request. Show the diff: three lines added to `terraform.tfvars`.
Within twenty seconds the check appears and passes, and a comment lands. Rehearsed at fifteen
seconds.

While the runner works, say what it is doing: `fmt -check`, `init` against the state bucket,
`validate`, then `plan`. Nothing it does can change infrastructure.

Read the comment aloud:

```
## Terraform plan for `9364ed7`

**Stage 2 · plan:** Plan: 0 to add, 2 to change, 0 to destroy.

**Stage 3 · policy:** passed

4 tests, 4 passed, 0 warnings, 0 failures, 0 exceptions
```

Expand **Full plan output**. Point at the `~` and at `# (12 unchanged attributes hidden)`.

**What to notice.** The reviewer reads the plan, not the HCL. Three lines of tfvars became two
in-place updates, and the comment says so before anyone approves anything. This is the review
artifact. Every later stage exists to stop a reviewed plan from being applied by the wrong hand.

### Step 3 · Merge, and meet the gate · slide 21 · 4 minutes

```sh
gh pr merge 5 --squash --delete-branch
```

Use the number the browser shows; the rehearsal's was 1. Switch to the **Actions** tab. The `apply`
workflow appears with two jobs. The first, **plan the merged commit**, runs and finishes. The
second, **stage 4 gate, then stage 5 apply**, shows an amber clock and the run page shows a yellow
banner: **Review deployments**.

Do not click yet. Open the plan job's summary. The plan is printed there, again, for the approver.

```
## Plan awaiting approval

Plan: 0 to add, 2 to change, 0 to destroy.
```

Now click **Review deployments**, tick `production`, and approve. The apply job starts and finishes
in about twenty seconds. Open its log and find:

```
google_storage_bucket.lake: Modifying... [id=YOUR_PROJECT_ID-cicd-lake]
google_storage_bucket.scratch: Modifying... [id=YOUR_PROJECT_ID-cicd-scratch]
google_storage_bucket.lake: Modifications complete after 1s [id=YOUR_PROJECT_ID-cicd-lake]
google_storage_bucket.scratch: Modifications complete after 0s [id=YOUR_PROJECT_ID-cicd-scratch]

Apply complete! Resources: 0 added, 2 changed, 0 destroyed.
```

Then, in the terminal:

```sh
gcloud storage buckets describe gs://YOUR_PROJECT_ID-cicd-scratch --format "yaml(labels)"
```

```
labels:
  cost-center: dsba6190
  env: dev
  managed-by: terraform
  owner: dsba6190
```

**What to notice.** Three things, in order. The gate sat between the plan and the apply, so the
approver approved a plan they could read, not a commit they had to imagine. The apply used the saved
plan from the first job, so what ran is exactly what was approved. And the approver was the author,
because this account is one person; say that GitHub can forbid self-review with one checkbox on the
environment, and that A4 expects the answer "someone who did not write the change."

### Step 4 · A public bucket · slide 23 · 3 minutes

```sh
gh pr create --base main --head demo/make-scratch-public --fill --web
```

Show the diff: one new resource, `google_storage_bucket_iam_member` with `member = "allUsers"`. The
check fails in about twenty seconds. Rehearsed at twenty-one.

While the runner works: a reviewer at 6 PM on a Friday might approve this. The plan will look small.

Read the comment:

```
**Stage 2 · plan:** Plan: 1 to add, 0 to change, 0 to destroy.

**Stage 3 · policy:** FAILED. This pull request cannot be merged until the plan satisfies policy.

FAIL - tfplan.json - main - google_storage_bucket_iam_member.public grants allUsers.
Public access to a bucket is not permitted.

4 tests, 3 passed, 0 warnings, 1 failure, 0 exceptions
```

Close the pull request from the browser.

**What to notice.** The gate named the resource and the reason, which a human reviewer might not
have. Then name the second layer: every bucket here sets `public_access_prevention = "enforced"`, so
if someone bypassed the pipeline and granted `allUsers` in the Console, the platform would refuse
too. Pipeline policy can explain itself; Organization Policy cannot be bypassed. A4 grades the
student on knowing both exist and which does what.

### Step 5 · The replace nobody announced · slide 25 · 3 minutes

```sh
gh pr create --base main --head demo/move-scratch --fill --web
```

Show the diff: one line, `location` changed from `var.region` to `"us-central1"`. A reviewer reading
HCL sees a region change. The check fails in about twenty seconds.

```
**Stage 2 · plan:** Plan: 1 to add, 0 to change, 1 to destroy.

**Stage 3 · policy:** FAILED. This pull request cannot be merged until the plan satisfies policy.

FAIL - tfplan.json - main - google_storage_bucket.scratch would be destroyed and recreated.
Add the label allow-replace = "true" to say that this is intended.
```

Close the pull request.

**What to notice.** `1 to add, 1 to destroy` on a one-line change. A bucket cannot move, so
Terraform plans to delete it and make a new one, and every object in it would go. The rule does not
forbid the replace; it requires the author to say out loud that they meant it. That is A4's
destructive-change prevention in one sentence: destruction requires a deliberate act.
`prevent_destroy` on the lake bucket is the other mechanism, and the hour-long demo performs it at
step 11.

### Step 6 · Drift · slide 21 · 5 minutes

In the Cloud Console tab, open the `cicd-scratch` bucket, edit its labels, and change `env` from
`dev` to `prod-by-accident`. Save. Say that this is a Friday-afternoon Console click that no commit
records.

```sh
gh workflow run drift
```

The scheduled workflow runs daily at 11:00 UTC. Running it by hand is the same code. Switch to the
**Issues** tab. Within twenty seconds, rehearsed at fourteen, an issue appears:

```
#4 Drift detected: reality differs from main
```

Open it. The body is the plan:

```
  # google_storage_bucket.scratch will be updated in-place
  ~ resource "google_storage_bucket" "scratch" {
      ~ labels                      = {
          ~ "env"         = "prod-by-accident" -> "dev"
```

While the runner works: this plan took no lock, so it never blocks a real apply, and it changed
nothing. Exit code 2 means a diff exists; the workflow turns that into an issue a person will see.

Now reconcile. Ask the room which side should win. Tonight, main wins: put the label back in the
Console, or run the drift workflow and then apply. Change the label back to `dev`, then:

```sh
gh workflow run drift
```

The issue closes itself with a comment naming the time.

**What to notice.** Drift detection is the only stage that runs on a timer. A4 asks how you find
drift and what you do when you find it; the answer has two halves, and the second half is a
decision, not a command. Sometimes reality should win, and then the fix is a commit, or an import.

### Step 7 · Close on A4 · 1 minute

Put the six-row table from the README back on screen and say which step answered which A4 question:

| A4 asks for | Evidenced at |
|---|---|
| Remote state, who can reach it, how it is protected | Step 1: a versioned bucket only the service account and the instructor can write |
| Approval controls, and from whom | Step 3: the `production` environment, required reviewer, self-review optional |
| Secrets, and how they reach a running apply | Step 1: federation, no key; application secrets stay in Secret Manager |
| Drift detection, and what you do when you find it | Step 6, both halves |
| Destructive-change prevention, the specific mechanisms | Step 5: the replace rule; and `prevent_destroy` on the lake bucket |
| Repository structure and environment isolation | Not shown. One environment, one directory. Say so, and point at the Session 4 slide on directory-per-environment |

---

## After class

Two of the buckets should stay if the demonstration runs again next term; they cost nothing. Destroy
them anyway the same evening, because the teardown is a teaching step and the runbook standard is
that nothing is left running.

```sh
cd ~/dsba6190-live-demo-04-cicd
git checkout main && git pull
sed -i '' '/prevent_destroy = true/s/true/false/' main.tf
terraform init -reconfigure \
  -backend-config="bucket=YOUR_PROJECT_ID-tfstate-cicd" \
  -backend-config="prefix=session-04-cicd"
terraform destroy
git checkout -- main.tf
gh workflow disable drift
```

The last line stops the daily drift plan. Against destroyed buckets it reports two missing buckets
as drift and opens an issue every morning. `live-setup.sh` enables it again before the next class.

The `sed` is the point, not a shortcut. `prevent_destroy` makes Terraform refuse, and the only way
through is a deliberate edit that never reaches `main`. Rehearsed output:

```
google_storage_bucket.lake: Destruction complete after 1s
google_storage_bucket.scratch: Destruction complete after 1s

Destroy complete! Resources: 2 destroyed.
```

### Teardown

Run this the same evening. Not tomorrow.

- [ ] **Destroy by the mechanism that created it.** `terraform destroy` as above, so state and reality
      agree on nothing existing.
- [ ] ~~**Compute.**~~ Nothing here creates any.
- [ ] ~~**Streaming.**~~
- [ ] ~~**Serving.**~~
- [ ] ~~**Managed services with an hourly floor.**~~
- [ ] ~~**Networking.**~~
- [ ] **Storage.** `cicd-lake` and `cicd-scratch` gone. The state bucket stays unless the
      demonstration is being retired; see below.
- [ ] ~~**Keys.**~~
- [ ] ~~**BigQuery.**~~
- [ ] ~~**Registry.**~~
- [ ] **GitHub.** Every demo branch deleted, every demo pull request closed, no open `drift` issue,
      and the drift workflow disabled. The notebook closes the two rejected pull requests with
      `--delete-branch`, and the merge deletes the third branch. The notebook's last cell lists
      what is left. Do not run `live-setup.sh` as the check, because it applies the buckets again.
- [ ] **Verify against billing, next morning.** Billing → Reports, filtered to the demo project,
      grouped by service, for yesterday. Expect Cloud Storage at $0.00 or $0.01.
- [ ] **Budget alert still armed.** The $50 budget on the project is unchanged.
- [ ] **Deliberate residue.** The repository, the state bucket, the service account, the Workload
      Identity pool and provider. They exist so the demonstration can run again. To retire it fully:

```sh
gh repo delete frazier-at-cpcc/dsba6190-infrastructure-pipeline
gcloud storage rm --recursive gs://YOUR_PROJECT_ID-tfstate-cicd
gcloud iam workload-identity-pools providers delete github \
  --workload-identity-pool github-actions --location global
gcloud iam workload-identity-pools delete github-actions --location global
gcloud iam service-accounts delete github-actions-tf@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

A deleted pool is soft-deleted for thirty days and its name cannot be reused until then. Retire it
only when the course is done with it.

---

## If it fails live

| Moment | What you see | Do this |
|---|---|---|
| Step 2, no comment after a minute | The check is red on an auth step | Open the log. If it names the federation, the condition and the repository disagree; present pull request 1 from the rehearsal instead and fix it after class |
| Step 3, no **Review deployments** banner | The apply job ran straight through | The environment lost its reviewer. Say so, show the environment settings page, and continue; the point survives |
| Step 3, apply fails on the lock | Another run holds the state | Wait for it. Never `force-unlock` a live holder |
| Step 6, no issue | The run is green but exit code was 0 | The label edit did not save, or hit the wrong bucket. Check the Console and run the workflow again |
| Anything, no network | Nothing | Pull requests 1 to 3 and issue 4 are the rehearsal's own record. Present them and say so |

---

## What is staged where

| Path | Purpose |
|---|---|
| `repo/` | Source of truth for the GitHub repository. `live-setup.sh` resets `main` to it |
| `repo/policy/buckets.rego` | The four rules. Rule numbers match the README |
| `bootstrap.sh` | One-time Google Cloud and GitHub setup. Idempotent. Re-run it after renaming the repository |
| `live-setup.sh` | Before class. Applies the baseline, pushes the three demo branches, enables the drift workflow, closes stale drift issues |
| `capture.sh` | The headless rehearsal. Never in class |
| `capture/` | Real output from the 10 September rehearsal, one file per step |
| `~/dsba6190-live-demo-04-cicd` | The clone `live-setup.sh` leaves, with `main` checked out and the backend initialised |
