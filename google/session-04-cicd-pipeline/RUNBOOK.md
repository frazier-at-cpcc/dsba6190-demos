# Session 4 walkthrough · An infrastructure pipeline with four gates

This walkthrough delivers two Cloud Storage buckets through a six-stage pipeline on GitHub Actions,
in seven steps. Every command below was run end to end on 10 September 2026, with Terraform v1.5.7,
`hashicorp/google` v5.45.2, Conftest v0.69.0, `google-github-actions/auth` v3 and
`hashicorp/setup-terraform` v4.0.1. `capture/` holds the full output of each step. You can read the
walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under $0.01: three Cloud Storage buckets holding kilobytes,
> and seven GitHub Actions runs totalling under three minutes of runner time. GitHub Actions minutes
> are free on a public repository. The state bucket, the service account and the federation remain
> between runs and cost nothing measurable. Delete what you create, in the order step 7 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `capture.sh` approves its own deployments through the API and closes its own pull
requests. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · A lake, a scratch bucket and a pipeline

The Terraform in `repo/` declares two buckets. The lake bucket holds data. It is versioned, and
`prevent_destroy` makes Terraform refuse to delete it. The scratch bucket holds nothing worth
keeping. It exists so the pipeline has something safe to change, rename and replace. Both buckets
enforce uniform access and public-access prevention, and both carry the labels `owner`, `env` and
`managed-by`.

No person applies a change to these buckets by hand. Every change travels through six stages:

| Stage | What happens | Where you read it |
|---|---|---|
| 1 | `fmt -check`, `init`, `validate` | The check on the pull request |
| 2 | `plan`, posted on the pull request | The sticky comment on the pull request |
| 3 | Conftest rejects the plan, and says why | The same comment, marked FAILED |
| 4 | A required reviewer opens the gate | Actions, the run page, **Review deployments** |
| 5 | `apply`, by a service account through federation | The apply job log |
| 6 | A scheduled `plan -detailed-exitcode` | An issue labelled `drift` |

The policy in `repo/policy/buckets.rego` holds four rules. Rule 1 forbids any binding to `allUsers`
or `allAuthenticatedUsers`. Rule 2 requires the labels `owner` and `env`. Rule 3 allows only
approved locations. Rule 4 forbids destroying and recreating a bucket unless the change carries the
label `allow-replace = "true"`.

---

## Before you start

You need a Google Cloud project with billing enabled, and a role on it that can create service
accounts, Workload Identity pools and IAM bindings. The project owner role is sufficient. You also
need a GitHub account.

Install and sign in to these tools:

- `gcloud`, signed in with `gcloud auth login`, and application default credentials from
  `gcloud auth application-default login`. The local Terraform in `live-setup.sh` uses them.
- `gh`, signed in to your GitHub account with `gh auth login`. Accept its offer to authenticate
  `git` over HTTPS, because `live-setup.sh` clones and pushes over HTTPS.
- Terraform 1.5, because `repo/versions.tf` requires `~> 1.5.7`, which excludes 1.6 and later.
- `git` and `python3`.

Choose a repository name under your own account, such as
`YOUR_GITHUB_USER/dsba6190-infrastructure-pipeline`. The steps below call it `OWNER/REPO`. Run the
one-time setup, then stage the walkthrough:

```sh
./bootstrap.sh  YOUR_PROJECT_ID OWNER/REPO    # once; it changes nothing that already exists
./live-setup.sh YOUR_PROJECT_ID OWNER/REPO    # or run prep.ipynb
source ~/dsba6190-live-demo-04-cicd/env.sh
cd ~/dsba6190-live-demo-04-cicd
```

`bootstrap.sh` enables five APIs and creates the versioned state bucket
`YOUR_PROJECT_ID-tfstate-cicd`. It creates the service account `github-actions-tf` and grants it
Storage Admin on the project. It creates a Workload Identity pool and a provider that trusts only
`OWNER/REPO`. On GitHub it creates the public repository if it is missing and sets four Actions
variables. It creates the `production` environment with you as the required reviewer, and it creates
the `drift` label. It creates no key.

`live-setup.sh` clones the repository into `~/dsba6190-live-demo-04-cicd` and resets `main` to
`repo/`. It applies the two buckets with your own credentials, so every plan in the walkthrough is a
change, not a create. It pushes three branches ready to become pull requests, enables the drift
workflow and closes any open drift issue. The reset commit carries `[skip ci]`, so no apply run
waits at the gate before you start.

Verify the staging:

```sh
gh run list --repo "$REPO" --limit 3
gcloud storage ls --project "$PROJECT" | grep cicd
```

Expect no run in progress, and three buckets: `cicd-lake`, `cicd-scratch` and `tfstate-cicd`.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Every cell that waits on GitHub Actions is a bounded loop. It returns when the
run completes and prints the run's conclusion and address. When a run reaches the gate, the cell
prints the browser instruction once and keeps waiting for your click. A cell that waits longer than
fifteen minutes stops and says so. Each run takes between fifteen and fifty seconds on a hosted
runner.

Keep four browser tabs open: the repository's **Pull requests**, **Actions**, **Issues** filtered to
`label:drift`, and the Cloud Console's **Cloud Storage** browser for your project.

---

## The sequence

| # | Step |
|---|---|
| 1 | The repository, and who it trusts |
| 2 | A compliant pull request |
| 3 | Merge, and meet the gate |
| 4 | A public bucket |
| 5 | The replace nobody announced |
| 6 | Drift |
| 7 | Teardown |

### Step 1 · The repository, and who it trusts

Open the repository README in the browser. Its table lists the six stages and the workflow that runs
each one. Then, in the terminal:

```sh
gh variable list
gcloud iam workload-identity-pools providers describe github \
  --workload-identity-pool github-actions --location global \
  --project "$PROJECT" --format "value(attributeCondition)"
```

Expect four variables, `WIF_PROVIDER`, `TF_SERVICE_ACCOUNT`, `TF_STATE_BUCKET` and
`TF_STATE_PREFIX`, and none of them is a secret. The condition names one repository. In the recorded
run it read as follows:

```
assertion.repository == 'frazier-at-cpcc/dsba6190-infrastructure-pipeline'
```

**What to notice.** The pipeline has no key. GitHub presents a signed token that names the
repository. Google Cloud trusts that token for this one repository and returns a token that lasts an
hour. Stage 5 runs as `github-actions-tf`, and nobody can download its credentials because it has
none.

### Step 2 · A compliant pull request

```sh
URL=$(gh pr create --base main --head demo/label-cost-center --fill) && PR=${URL##*/}
gh pr view "${PR:?}" --web
```

The diff adds three lines to `terraform.tfvars`. The check appears and passes, and a comment lands.
In the recorded run the check job ran for **12 seconds**. The job runs `fmt -check`, `init` against
the state bucket, `validate`, then `plan`. Nothing it does can change infrastructure. The comment
from the recorded run reads:

```
## Terraform plan for `9364ed7`

**Stage 2 · plan:** Plan: 0 to add, 2 to change, 0 to destroy.

**Stage 3 · policy:** passed

4 tests, 4 passed, 0 warnings, 0 failures, 0 exceptions
```

Expand **Full plan output** and find the `~` markers and `# (12 unchanged attributes hidden)`.

**What to notice.** The reviewer reads the plan, not the HCL. Three lines of tfvars became two
in-place updates, and the comment says so before anyone approves anything. The plan is the review
artifact. Every later stage exists to stop a reviewed plan from being applied by the wrong hand.

### Step 3 · Merge, and meet the gate

```sh
gh pr merge "${PR:?}" --squash --delete-branch
```

Switch to the **Actions** tab. The `apply` workflow appears with two jobs. The first, **plan the
merged commit**, runs and finishes. The second, **stage 4 gate, then stage 5 apply**, shows an amber
clock, and the run page shows a yellow banner, **Review deployments**. The recorded run captured
that state:

```
plan the merged commit: completed success
stage 4 gate, then stage 5 apply: waiting
```

Before you approve, open the plan job's summary. The job prints the plan there again, under the
heading **Plan awaiting approval**, for the approver. Then click **Review deployments**, tick
`production` and approve. The apply job finishes in about twenty seconds. Its log in the recorded
run ends:

```
google_storage_bucket.scratch: Modifying... [id=YOUR_PROJECT_ID-cicd-scratch]
google_storage_bucket.lake: Modifying... [id=YOUR_PROJECT_ID-cicd-lake]
google_storage_bucket.lake: Modifications complete after 0s [id=YOUR_PROJECT_ID-cicd-lake]
google_storage_bucket.scratch: Modifications complete after 0s [id=YOUR_PROJECT_ID-cicd-scratch]

Apply complete! Resources: 0 added, 2 changed, 0 destroyed.
```

Then confirm the result in the cloud:

```sh
gcloud storage buckets describe "gs://$SCRATCH_BUCKET" --format "yaml(labels)"
```

```
labels:
  cost-center: dsba6190
  env: dev
  managed-by: terraform
  owner: dsba6190
```

**What to notice.** The gate sat between the plan and the apply, so you approved a plan you could
read, not a commit you had to imagine. The apply used the saved plan from the first job, so what ran
is exactly what you approved. You approved your own change, because one person owns this repository.
GitHub can forbid self-review with one setting on the environment.

### Step 4 · A public bucket

```sh
URL=$(gh pr create --base main --head demo/make-scratch-public --fill) && PR=${URL##*/}
gh pr view "${PR:?}" --web
```

The diff adds one resource, `google_storage_bucket_iam_member`, with `member = "allUsers"`. The
check fails. In the recorded run the job ran for **18 seconds**, and the comment read:

```
**Stage 2 · plan:** Plan: 1 to add, 0 to change, 0 to destroy.

**Stage 3 · policy:** FAILED. This pull request cannot be merged until the plan satisfies policy.

FAIL - tfplan.json - main - google_storage_bucket_iam_member.public grants allUsers.
Public access to a bucket is not permitted.

4 tests, 3 passed, 0 warnings, 1 failure, 0 exceptions
```

Close the pull request:

```sh
gh pr close "${PR:?}" --delete-branch
```

**What to notice.** The plan looks small, and a tired human reviewer might approve it. The gate
named the resource and the reason. A second layer stands behind it. Every bucket here sets
`public_access_prevention = "enforced"`, so the platform refuses the grant even when someone
bypasses the pipeline and grants `allUsers` in the Console. Pipeline policy can explain itself.
Organization Policy cannot be bypassed.

### Step 5 · The replace nobody announced

```sh
URL=$(gh pr create --base main --head demo/move-scratch --fill) && PR=${URL##*/}
gh pr view "${PR:?}" --web
```

The diff changes one line. The scratch bucket's `location` moves from `var.region` to
`"us-central1"`. A reviewer reading the HCL sees a region change. The check fails, and in the
recorded run the job ran for **16 seconds**:

```
**Stage 2 · plan:** Plan: 1 to add, 0 to change, 1 to destroy.

**Stage 3 · policy:** FAILED. This pull request cannot be merged until the plan satisfies policy.

FAIL - tfplan.json - main - google_storage_bucket.scratch would be destroyed and recreated.
Add the label allow-replace = "true" to say that this is intended.
```

Close the pull request:

```sh
gh pr close "${PR:?}" --delete-branch
```

**What to notice.** A one-line change planned `1 to add` and `1 to destroy`. A bucket cannot move,
so Terraform plans to delete it and create a new one, and every object in it would be lost. The rule
does not forbid the replace. It requires the author to state that the replace is intended. Rule 4
makes destruction a deliberate act. `prevent_destroy` on the lake bucket is the other mechanism, and
the companion Session 4 demonstration, Migrate state, then break it, exercises it.

### Step 6 · Drift

Change a label outside the pipeline. In the Cloud Console, open the `cicd-scratch` bucket, edit its
labels and change `env` from `dev` to `prod-by-accident`. The notebook carries the same edit as a
command:

```sh
gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=prod-by-accident --project "$PROJECT"
gh workflow run drift
```

The scheduled workflow runs daily at 11:00 UTC, and running it by hand runs the same code. In the
recorded run the drift job ran for **12 seconds**, and an issue appeared on the **Issues** tab:

```
#4 Drift detected: reality differs from main
```

The issue body is the plan:

```
  # google_storage_bucket.scratch will be updated in-place
  ~ resource "google_storage_bucket" "scratch" {
      ~ labels                      = {
          ~ "env"         = "prod-by-accident" -> "dev"
```

This plan took no lock, so it never blocks a real apply, and it changed nothing. Exit code 2 means a
diff exists, and the workflow turns that exit code into an issue a person will see.

Now reconcile. Here `main` wins, so put the label back and run the check again:

```sh
gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=dev --project "$PROJECT"
gh workflow run drift
```

The run exits 0, and the issue closes itself with a comment that names the time. The recorded run
listed `#4 Drift detected: reality differs from main CLOSED`.

**What to notice.** Drift detection is the only stage that runs on a timer. Finding drift is a
command. Deciding which side wins is a decision. When reality should win, the fix is a commit or an
import.

### Step 7 · Teardown

```sh
cd "${WORKDIR:?}"
git checkout main && git pull
sed -i '' '/prevent_destroy = true/s/true/false/' main.tf
terraform init -reconfigure \
  -backend-config="bucket=${STATE_BUCKET:?}" \
  -backend-config="prefix=${STATE_PREFIX:?}"
terraform destroy
git checkout -- main.tf
gh workflow disable drift
```

The `sed` line is deliberate. `prevent_destroy` makes Terraform refuse, and the only way through is
an edit that never reaches `main`. The last line stops the daily drift plan, which would otherwise
report the two missing buckets as drift and open an issue every morning. The recorded run ended:

```
google_storage_bucket.lake: Destruction complete after 1s
google_storage_bucket.scratch: Destruction complete after 1s

Destroy complete! Resources: 2 destroyed.
```

The last cell of `demo.ipynb` lists what remains: buckets, open pull requests, open drift issues and
remote branches. Expect only the state bucket and `main`. Do not run `live-setup.sh` as a check,
because it applies the buckets again.

The repository, the state bucket, the service account, and the Workload Identity pool and provider
remain so that you can run the demonstration again. To remove them as well:

```sh
gh repo delete "${REPO:?}"
gcloud storage rm --recursive "gs://${STATE_BUCKET:?}"
gcloud iam workload-identity-pools providers delete github \
  --workload-identity-pool github-actions --location global --project "${PROJECT:?}"
gcloud iam workload-identity-pools delete github-actions --location global --project "${PROJECT:?}"
gcloud iam service-accounts delete "github-actions-tf@${PROJECT:?}.iam.gserviceaccount.com" --project "${PROJECT:?}"
```

Every name is written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong
thing. A deleted pool is soft-deleted for thirty days, and its name cannot be reused until then. The
next day, open the billing reports for your project, group by service, and confirm that Cloud
Storage shows $0.00 or $0.01.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| A run log shows `Unable to acquire impersonated credentials` | The federation condition names a different repository. Run `./bootstrap.sh` again with the right `OWNER/REPO`. It updates the condition |
| The plan job fails with `403 ... storage.buckets.create` | The service account lost Storage Admin. Run `./bootstrap.sh` again. The binding is idempotent |
| The apply job runs without stopping at **Review deployments** | The `production` environment has no reviewer. Required reviewers need a public repository or a paid plan. Keep the repository public and run `./bootstrap.sh` again |
| No plan comment appears on the pull request | A pull request from a fork gets no `id-token` and no `pull-requests: write`. Open pull requests from branches in the repository itself |
| `Error acquiring the state lock` | A previous run is still applying, or a local terminal holds the lock. Wait for the run. Use `terraform force-unlock` only when the holder is dead |
| A pull-request check sits in **Queued** and never starts | An apply run is waiting at the gate and holds the `terraform-state` concurrency group. Approve or reject that run under **Actions** |
| Step 6 opens no issue, and the drift run is green | The run exited 0, so the label edit did not save or changed the wrong bucket. Check the Console and run the workflow again |
| The drift run fails with `label not found` | The `drift` label is missing. Run `gh label create drift --repo OWNER/REPO` |
| `live-setup.sh` prints `exists but is not in state. Importing it.` | No action is needed. The script adopts the bucket before it applies. Without the import, the apply fails with `409` |
| `terraform init` in `live-setup.sh` reports an unsupported Terraform version | `repo/versions.tf` requires `~> 1.5.7`. Install a Terraform 1.5 release |
| The teardown `sed` line fails with `No such file or directory` | `sed -i ''` is the BSD form. With GNU `sed`, drop the empty argument: `sed -i '/prevent_destroy = true/s/true/false/' main.tf` |
| An open `drift` issue appears the morning after the teardown | The daily drift plan ran against the destroyed buckets. Run `gh workflow disable drift`. `live-setup.sh` enables it again |
| A notebook cell prints `No ... run after 120 s` | GitHub did not create the run, often because the push or dispatch failed. Read the cell's earlier output and the **Actions** tab, then rerun the cell |
| A check you did not write appears, such as CodeRabbit in the recorded run | An app installed on the GitHub account reviews public repositories. It is not part of the pipeline. Ignore it, or uninstall it in the account settings |
| A push that adds `.github/workflows/` is refused for a missing `workflow` scope | Run `gh auth refresh -h github.com -s workflow`, then run `live-setup.sh` again |
| `gh repo delete` refuses with a missing scope | Run `gh auth refresh -h github.com -s delete_repo`, then delete again |

---

## Files

| Path | What it is |
|---|---|
| `repo/` | The pipeline repository. `live-setup.sh` resets `main` to it |
| `repo/policy/buckets.rego` | The four policy rules. Rule numbers match the repository README |
| `repo/.github/workflows/` | `pull-request.yml` for stages 1 to 3, `apply.yml` for stages 4 and 5, `drift.yml` for stage 6 |
| `bootstrap.sh` | One-time Google Cloud and GitHub setup. Run it again after renaming the repository |
| `live-setup.sh` | Applies the baseline, pushes the three branches, enables the drift workflow and closes stale drift issues |
| `capture.sh`, `capture/` | The recorder and the real output of the run on 10 September 2026, one file per step |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
