# Session 3 live demo · runbook

Monolith to module, then hardened for A3. One hour, thirteen steps, 1:30 to 2:30.

Rehearsed end to end on 27 September 2026 against project `YOUR_PROJECT_ID`: Terraform v1.5.7,
`hashicorp/google` v5.45.2, Cloud Storage in `US-EAST1`, and one Compute Engine `e2-micro` in
`us-east1-b`. Every command below was run, and `capture/` holds the full output of each one. The
headless recorder completed all thirteen steps in 231 seconds. The notebooks completed them in 238.

**Do not run `capture.sh` in class.** It stages its own working directory and deletes everything
through an exit trap. `live-setup.sh` stages and never destroys.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. Reproducing it on your own account costs
> less than one cent: four empty or near-empty buckets, and an `e2-micro` that lives for under three
> minutes at a list price of $0.008376 an hour. **Destroy what you create, in the order step 13
> shows.**

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is fictional: a twelve-person analytics firm in South End, Charlotte,
that sells trip-demand dashboards to ground-transportation fleets. Each night a fleet drops one file
of completed trips into a bucket. In Session 1 someone created that bucket by hand in the Console,
and nobody wrote down its settings.

Tonight the firm codifies the nightly-trips bucket. Steps 1 to 7 are the refactor: a flat
configuration, read and applied, changed in place, nearly replaced, drifted, and turned into one
module called for `dev` and `prod`. Steps 8 to 13 harden that module the way A3 asks: validated
inputs, labels a caller cannot override, deletion controls that hold with data inside, environments
from one map, the Lab 3 virtual machine behind a five-input interface, and drift reported as an exit
code. The course project hosts the run, so every name begins with `dsba6190` and ends with a random
suffix.

Introduce the firm on the scenario slide in about two minutes, then open each step with one sentence
of what the firm is doing. The slide notes carry that sentence.

---

## How the hour fits the session clock

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Declarative infrastructure | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Making it reusable | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | A3 workshop, then Lab 3 supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

---

## Before class

```sh
cd "lectures/demos/session-03-monolith-to-module"
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb; T minus 30
cd ~/dsba6190-live-demo-03 && terraform plan  # Plan: 1 to add, 0 to change, 0 to destroy.
```

The script builds `~/dsba6190-live-demo-03`, copies every stage into it, writes `terraform.tfvars`
and `env.sh`, and runs `terraform init`. It creates nothing in the project, because step 2 must plan
against an empty project. It refuses to overwrite a working directory whose state still tracks
resources. The prep notebook ran in 11 seconds on the rehearsal.

| Symptom | Cause | Fix |
|---|---|---|
| `could not find default credentials` | Application default credentials expired | `gcloud auth application-default login` |
| `403 does not have storage.buckets.create` | Wrong active project or account | `gcloud config set project YOUR_PROJECT_ID` |
| `live-setup.sh` stops with `still tracks resources` | A previous run was not torn down | Run the teardown it prints, then stage again |
| `bucket already exists` | A name from an earlier run is taken | Stage again; the script derives a new suffix |

**Drive the hour from `demo.ipynb`** on the Bash kernel: VS Code, **Select Kernel**, **Jupyter
Kernel**, **Bash**. Keep a browser tab on Cloud Storage in the demo project, because steps 6 and 12
make their label edits in the Console. The notebook's `gcloud` cells make the same edits when the
Console is not an option.

---

## The sequence

| # | Step | Minutes | Slide |
|---|---|---|---|
| 1 | The nightly-trips bucket as a flat `main.tf` | 3 | 38 |
| 2 | `plan`: read the diff before you cause it | 3 | 39 |
| 3 | `apply`, then `apply` again | 4 | 40 |
| 4 | Storage class: `~` update in place | 3 | 41 |
| 5 | Bucket name: `-/+` destroy and recreate. Stop | 4 | 42 |
| 6 | A Console label edit: `plan` finds the drift | 4 | 43 |
| 7 | One module, called for `dev` and `prod` | 5 | 44 |
| 8 | Validation refuses a typo; enforced labels overrule a caller | 6 | 45 |
| 9 | `prevent_destroy`, then `force_destroy`, refuse the delete | 6 | 46 |
| 10 | Environments from one map with `for_each` | 5 | 47 |
| 11 | The Lab 3 VM as a module: validated, protected, priced | 8 | 48 |
| 12 | Drift as an exit code, and the lock file | 5 | 49 |
| 13 | Teardown, and proof that nothing remains | 4 | 50 |
| | **Total** | **60** | |

Slide 34 is the divider, slide 35 introduces the scenario, and slides 36 and 37 carry the run sheet.
Slides 51 to 54 are the A3 workshop that follows. The deck runs to 60 slides.

Every command runs from `~/dsba6190-live-demo-03`. `terraform.tfvars` holds the project and the
suffix, so no command needs a flag it does not show.

### Step 1 · The monolith · 3 minutes

```sh
cat main.tf
```

Name what is hardcoded: the name, the location, and the storage class. `force_destroy = true` is
there only so the first seven steps tear down in one command. **What to notice.** This is the bucket
someone clicked into existence in Session 1, now in a file a reviewer can read.

### Step 2 · Read the diff before you cause it · 3 minutes

```sh
terraform plan
```

`Plan: 1 to add, 0 to change, 0 to destroy.` Read the symbol, the address, then the attributes.
**What to notice.** `(known after apply)` names what Terraform cannot know until Google answers.

### Step 3 · Apply, then apply again · 4 minutes

```sh
terraform apply -auto-approve
terraform apply -auto-approve
```

The bucket was created in **1 second**. The second run printed `No changes. Your infrastructure
matches the configuration.` **What to notice.** A script would fail on the second run, because
`create` on an existing bucket is an error.

### Step 4 · Update in place · 3 minutes

```sh
cp main.tf.nearline main.tf && terraform plan
terraform apply -auto-approve
```

`~ storage_class = "STANDARD" -> "NEARLINE"` with **14 unchanged attributes hidden**, then `0 added,
1 changed, 0 destroyed` in under a second. **What to notice.** The bucket keeps its name, its
objects, and its URL.

### Step 5 · Destroy and recreate. Stop · 4 minutes

```sh
cp main.tf.renamed main.tf && terraform plan
cp main.tf.nearline main.tf
```

`-/+ destroy and then create replacement`, and on the `name` line, `# forces replacement`. `Plan: 1
to add, 0 to change, 1 to destroy.` **Do not apply.** Ask what would have happened if this bucket
held the fleet's raw trips, and let the silence run. Restore `main.tf.nearline` before step 6.
**What to notice.** `forces replacement` is the string to search for in any plan you did not write.

### Step 6 · Terraform finds the drift · 4 minutes

In the Console, open the bucket, edit its labels, set `owner` to `someone-at-2am`, and save. Then:

```sh
terraform plan
```

`~ "owner" = "someone-at-2am" -> "dsba6190"` in all three label maps, and `Plan: 0 to add, 1 to
change, 0 to destroy.` **What to notice.** This is detection. Nothing prevented the edit.

### Step 7 · One module, two environments · 5 minutes

```sh
terraform destroy -auto-approve
cp main.tf.module main.tf && terraform init
terraform plan
terraform apply -auto-approve
```

`Plan: 2 to add`, two buckets created in **1 second** each, and two outputs. **`terraform init` is
not optional.** Skip it and `plan` fails with `Error: Module not installed`. **What to notice.** The
four standard labels come from the module body, so a caller cannot forget them.

### Step 8 · Validation, and labels a caller cannot override · 6 minutes

```sh
cp -R stages/05-validate/. . && terraform init
cp main.tf.typo main.tf && terraform plan
cp stages/05-validate/main.tf main.tf && terraform plan
terraform apply -auto-approve
terraform output dev_labels
```

The typo `environment = "production"` fails at plan time with `environment must be one of: dev,
test, prod.` The corrected root passes `extra_labels` with `environment = "sandbox"` and `team =
"fleet-dashboards"` to the dev lake. The plan adds `team` to both buckets and leaves `environment`
alone, and `terraform output dev_labels` shows `"environment" = "dev"`. **What to notice.**
`merge(var.extra_labels, local.enforced)` puts the enforced map last, so it wins.

### Step 9 · Safe deletion: prevent_destroy, then force_destroy · 6 minutes

```sh
cp -R stages/06-protect/. . && terraform apply -auto-approve
gcloud storage cp trips-2026-09-02.csv "gs://${PROD_BUCKET:?}/raw/"
terraform destroy -auto-approve
cp modules/data-lake/main.tf.unguarded modules/data-lake/main.tf
terraform destroy -auto-approve -target=module.prod_lake
gcloud storage ls "gs://${PROD_BUCKET:?}/raw/"
```

The apply shows `~ force_destroy = true -> false` on both buckets. The first destroy fails twice
with `Error: Instance cannot be destroyed`, once per bucket, because `lifecycle.prevent_destroy`
accepts literal values only and so guards every environment. With the lifecycle block deleted, the
targeted destroy fails with `Error trying to delete bucket dsba6190-prod-raw-26095 containing
objects without force_destroy set to true`. The trip file is still listed. **What to notice.**
Deleting the block deleted the guard. The second control held anyway.

### Step 10 · Environments from one map · 5 minutes

```sh
cp -R stages/07-foreach/. . && terraform init && terraform plan
terraform apply -auto-approve
cp main.tf.test main.tf && terraform plan
terraform apply -auto-approve
```

The first plan reads `module.dev_lake... has moved to module.lake["dev"]` for both buckets and
`Plan: 0 to add, 0 to change, 0 to destroy.` Adding `test` to the map plans **exactly 1 to add**.
**What to notice.** Without the two `moved` blocks, the new addresses would have planned the
destruction of dev and prod. All three environments still share one state.

### Step 11 · The Lab 3 VM as a module · 8 minutes

```sh
cp -R stages/08-vm/. . && terraform init
terraform plan -var machine_type=n2-standard-32
terraform apply -auto-approve
gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet
terraform apply -auto-approve -var vm_environment=dev
cp stages/07-foreach/main.tf.test main.tf && terraform apply -auto-approve
```

| What happened | Real figure |
|---|---|
| `n2-standard-32` at plan time | `machine_type must be e2-micro, e2-small, or e2-medium.` |
| `e2-micro`, environment `prod`, created | 13 seconds, `deletion_protection = true` |
| `gcloud compute instances delete` | `Resource cannot be deleted if it's protected against deletion.` |
| Protection off through Terraform | 23-second in-place update, labels and tags `prod` to `dev` |
| Module call removed, instance destroyed | 1 minute 54 seconds |
| Apply to destroyed, wall clock | **159 seconds, 0.0442 machine-hours, $0.000370** |
| `n2-standard-32` list price | **$1.5539 an hour, $1,134.34 for a 730-hour month** |

The prices come from the Cloud Billing Catalog for `us-east1` on 27 September 2026: E2 cores at
$0.02181159 an hour and E2 memory at $0.00292353 a GiB-hour, with an `e2-micro` billed as a quarter
of a core and 1 GiB. **What to notice.** The cost model is machine type multiplied by hours running,
and the validation block refuses the expensive value before anything bills.

### Step 12 · Drift as an exit code, and reproducibility · 5 minutes

```sh
terraform plan -detailed-exitcode > /dev/null; echo "exit code $?"
terraform plan -detailed-exitcode | grep -E "owner|Plan:"; echo "exit code ${PIPESTATUS[0]}"
sed -n '1,12p' .terraform.lock.hcl
terraform providers
```

Make the `owner` label edit on the prod bucket in the Console between the first two commands. The
first plan returned **exit code 0**; after the edit, **exit code 2**. The lock file records `version
= "5.45.2"` under `constraints = "~> 5.0"`, with hashes. **What to notice.** Exit code 2 is the hook
a scheduled pipeline uses next week, and the committed lock file is what makes the next checkout
resolve the same provider.

### Step 13 · Teardown, and proof that nothing remains · 4 minutes

```sh
gcloud storage rm "gs://${PROD_BUCKET:?}/**"
cd "${WORKDIR:?}" && terraform destroy -auto-approve
gcloud storage buckets list --filter="name~${SUFFIX:?}" --format="value(name)"
gcloud compute instances list --filter="name~${SUFFIX:?}" --format="value(name)"
terraform state list
```

Empty the prod bucket on purpose first, because `force_destroy` is false. The destroy removed three
buckets in about a second each. The listings returned **0 buckets and 0 instances**, and the state
held 0 resources. **What to notice.** Every destructive command names its target as `${VAR:?}`, so
an empty variable refuses to run rather than widening the delete.

---

## If it fails live

| What happened | Do this |
|---|---|
| `apply` hangs longer than about twenty seconds | Ctrl-C once, then present the capture slide for that step. Every slide from 38 to 50 is real output |
| `Error: Module not installed` at step 7, 10, or 11 | Run `terraform init`. The step's first cell includes it |
| Step 9's first destroy succeeds | The stage copy was skipped, so the module has no lifecycle block. Recreate with `terraform apply` and copy the stage |
| The VM apply fails on quota or zone capacity | Present slide 48. Do not debug a VM in front of the room |
| Credentials expire mid-session | Move to the capture slides and say plainly that the run is recorded |
| The hour runs short | Shorten step 12 to the two exit codes. Never skip step 9 or step 13 |

The capture slides are the same run, recorded on 27 September 2026. Switching to them costs the room
nothing except the sight of the command being typed.

---

## Files

| Path | What it is |
|---|---|
| `01-monolith/` to `04-module/` | Steps 1 to 7: the flat bucket, the storage class, the rename, and the data-lake module |
| `05-validate/` | Step 8: validated inputs, `extra_labels`, `merge()` with the enforced map last, and `main.tf.typo` |
| `06-protect/` | Step 9: `force_destroy` as an input defaulting to false, `prevent_destroy`, and `main.tf.unguarded` |
| `07-foreach/` | Step 10: one module block over a map, two `moved` blocks, and `main.tf.test` |
| `08-vm/` | Step 11: the Lab 3 VM as a five-input module with a validated machine type |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and 44 files of real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
