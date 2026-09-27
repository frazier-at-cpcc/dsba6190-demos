# Session 4 walkthrough · Migrate state, then break it

This walkthrough moves a small Terraform estate from local state to a versioned Cloud Storage
backend in eleven steps, then breaks that backend in each way it exists to survive. Every command
below was run end to end on 10 September 2026 with Terraform v1.5.7, `hashicorp/google` v5.45.2,
`hashicorp/random` v3.9.0 and `hashicorp/time` v0.14.1, and `capture/` holds the full output of each
one. You can read the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under $0.05: four Cloud Storage buckets, one Pub/Sub topic
> and a few kilobytes of objects. The largest line is the state bucket, because versioning keeps
> every generation and the demonstration writes state twenty times. Delete what you create, in the
> order the teardown section shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Queen City Trip Analytics

**Queen City Trip Analytics** is a fictional twelve-person analytics firm in South End, Charlotte,
that sells trip-demand dashboards to ground-transportation fleets. In Session 3 it codified its
nightly-trips bucket with Terraform, on one engineer's laptop. This month a second engineer joins,
and state that lives on one laptop becomes the company's largest risk. The company moves its state
to a shared, versioned, locked backend, and then meets each failure that backend exists to survive.

The scenario renames no resource and changes no command. The table names what each resource is to
the company.

| Demo resource | What it is in the scenario |
|---|---|
| `google_storage_bucket.raw`, `dsba6190-raw-<SUFFIX>` | The trip bucket, where fleets drop their nightly trip files |
| `google_pubsub_topic.events`, `dsba6190-events-<SUFFIX>` | The topic that carries trip events to the dashboards |
| `random_password.db_admin` | The admin credential for the dashboard database. Terraform generated it, so Terraform stores it, and that is why state is sensitive |
| `dsba6190-tfstate-<SUFFIX>`, created by hand in step 2 | The shared state bucket both engineers use from now on |
| `google_storage_bucket.legacy`, `dsba6190-legacy-<SUFFIX>` | An archive bucket someone created by hand in the Console before the company adopted Terraform. Nobody wrote down its settings |
| `google_storage_bucket.annex`, `dsba6190-annex-<SUFFIX>` | A cold-storage annex made the same way, which the company adopts through a reviewed `import` block |
| `time_sleep.slow_apply` | It has no business meaning. It holds an apply open long enough for the lock to be visible |
| The second terminal in steps 5 and 6 | The engineer who joined this month |
| `report.csv` in step 11 | A fleet customer's quarterly totals, of which nobody has a copy |

The estate holds no real trips. The trip bucket stays empty until step 11 writes one file, and the
password protects no database.

---

## Before you start

You need the Google Cloud CLI, Terraform 1.5 or later, a project with billing enabled, and
application default credentials from `gcloud auth application-default login`.

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
cd ~/dsba6190-live-demo-04
terraform plan
```

Expect `No changes. Your infrastructure matches the configuration.`

Unlike the Session 3 setup, this script applies. The demonstration begins from an estate that
already exists on local state, so the script builds that estate with the local backend. It also
creates two buckets by hand, because steps 8 and 10 need resources Terraform did not build. It does
not create the state bucket, because creating the state bucket is step 2. The script prints the
working directory, the name suffix, every bucket name and the teardown commands. Note the suffix.

The script also stages every file variant the steps copy into place, so no step requires editing.

| Staged file | Step | What it is |
|---|---|---|
| `main.tf` | 1 | The baseline: a bucket, a topic and a generated password |
| `terraform.tfvars` | all | The project and name suffix, so no command needs a `-var` flag |
| `backend.tf.staged` | 3 | The `backend "gcs"` block with the bucket name filled in |
| `main.tf.sleep` | 5 | Adds `time_sleep`, which holds the lock for ninety seconds |
| `legacy.tf.guess` | 8 | The configuration written from memory, which is wrong |
| `legacy.tf.matched` | 8 | The configuration the plan asked for |
| `annex.tf.staged` | 8 | The plannable `import` block with the id filled in |
| `main.tf.renamed` | 10 | The bucket's address changed to `landing` |
| `main.tf.protected` | 11 | `prevent_destroy` on the bucket |
| `main.tf.forced` | 11 | `force_destroy = true` on the bucket |

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. A notebook cell cannot answer a `yes` prompt, so the notebook adds
`-auto-approve` to every apply and destroy and `-force-copy` to the migration. Steps 5 and 6 need
two terminals when you run them by hand. The notebook runs the first terminal's apply as a
background job and shows its log afterwards. Keep the Cloud Console open on Cloud Storage for steps
2, 3, 8 and 9. The full recorded run takes about twenty minutes, and two steps wait on a
ninety-second `time_sleep`.

---

## The sequence

Every command runs from `~/dsba6190-live-demo-04`. Each step leaves the precondition the next one
needs, so run them in order.

| # | Step |
|---|---|
| 1 | Read the state you already have |
| 2 | Bootstrap the state bucket, with versioning |
| 3 | The backend block, and the migration |
| 4 | Plan says no changes |
| 5 | Two terminals, one lock |
| 6 | The crashed run, and `force-unlock` |
| 7 | Versioning is the undo |
| 8 | Import what somebody built by hand |
| 9 | Drift, and which side should win |
| 10 | Surgery on the record |
| 11 | Refuse to destroy, then permit it |

### Step 1 · Read the state you already have

Queen City's state lives on the founding engineer's laptop, and a second engineer now needs it.

```sh
terraform state list
terraform output
terraform state show random_password.db_admin
grep -o '"result": "[^"]*"' terraform.tfstate
```

`state list` returns three addresses: `google_pubsub_topic.events`, `google_storage_bucket.raw` and
`random_password.db_admin`. `terraform output` prints `db_admin_password = <sensitive>`, and `state
show` prints `result = (sensitive value)`. The `grep` prints the password in full, in plain text.
**What to notice.** State is what Terraform believes it manages, which differs from both the project
and the configuration. `sensitive = true` suppresses the console and does nothing to the file. The
file sits next to the configuration, one `git add .` away from a public repository.

### Step 2 · Bootstrap the state bucket, with versioning

Before the new engineer runs anything, Queen City builds the bucket its state will share.

```sh
gcloud storage buckets create gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID --location=US-EAST1 \
  --uniform-bucket-level-access --public-access-prevention

gcloud storage buckets update gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID --versioning

gcloud storage buckets describe gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"
```

The description shows `location: US-EAST1`, `public_access_prevention: enforced`,
`uniform_bucket_level_access: true` and `versioning_enabled: true`. **What to notice.** Uniform
access removes per-object permissions, public access prevention blocks accidental sharing, and
versioning is the undo that step 7 uses. Data Access audit logging is a fourth control, and it is a
project setting rather than a bucket setting. The bucket is created by hand because `terraform init`
refuses a backend whose bucket does not exist. A configuration cannot create the bucket that holds
its own state.

### Step 3 · The backend block, and the migration

Queen City moves its state off the laptop and into the shared bucket, and the database credential
moves with it.

```sh
cp backend.tf.staged backend.tf
cat backend.tf
terraform init -migrate-state
```

`bucket` names the state bucket. `prefix` is `envs/dev`, which lets one bucket hold several
environments as separate objects. Answer `yes` at the prompt. The run printed `Successfully
configured the backend "gcs"!`

```sh
gcloud storage ls -r gs://dsba6190-tfstate-<SUFFIX>
gcloud storage cat gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  | grep -o '"result": "[^"]*"'
```

The bucket holds `envs/dev/default.tfstate`, and the same password string from step 1 is inside it.
**What to notice.** The staged file is a template that `live-setup.sh` filled in, because a backend
block may not contain a variable. In a real repository the answer is partial configuration plus
`-backend-config` on the command line. The state bucket is now a secret store. Its IAM policy is a
production access-control decision. Never answer `no` at the prompt, and never use `-reconfigure`
instead. Either one starts the new backend empty, and the next plan proposes to build the whole
estate a second time.

### Step 4 · Plan says no changes

Queen City confirms that moving the record changed nothing in its estate, then cleans the laptop.

```sh
terraform plan
ls -l terraform.tfstate*
grep -o '"result": "[^"]*"' terraform.tfstate.backup
rm terraform.tfstate terraform.tfstate.backup
```

The plan prints `No changes. Your infrastructure matches the configuration.` The listing shows a
zero-byte `terraform.tfstate` and a **4,599-byte** `terraform.tfstate.backup`, and the password is
still in the backup. **What to notice.** The record moved, and reality did not. Migration cleaned up
nothing. The secret stayed on the laptop in a file whose name nobody thinks to check, so the last
command deletes both files.

### Step 5 · Two terminals, one lock

Both Queen City engineers run Terraform against the same estate at the same moment. The first
terminal is the founding engineer, and the second is the engineer who joined this month.

```sh
cp main.tf.sleep main.tf
terraform apply                  # first terminal, answer yes
terraform plan                   # second terminal, while the apply runs
```

`time_sleep` costs nothing and blocks the apply for ninety seconds. The second terminal fails:

```
Error: Error acquiring the state lock

Error message: writing "gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tflock"
failed: googleapi: Error 412: At least one of the pre-conditions you
specified did not hold., conditionNotMet
Lock Info:
  ID:        1789046532656217
  Path:      gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tflock
  Operation: OperationTypeApply
  Who:       <user>@<host>
  Version:   1.5.7
  Created:   2026-09-10 13:22:12.550084 +0000 UTC
```

**What to notice.** The `Lock Info` block names who holds the lock, which operation they are
running, and when they took it. The mechanism is a `.tflock` object and HTTP 412, an
object-generation precondition, with no lock table or extra infrastructure. The error ends by
offering `-lock=false`. The tool cannot stop you from using it, and using it is how concurrent
writes corrupt state. Let the first terminal finish before you continue.

### Step 6 · The crashed run, and `force-unlock`

An apply on one Queen City laptop dies mid-run, and the lock it took stays behind.

```sh
terraform apply -replace=time_sleep.slow_apply     # answer yes, wait about 20 s
# Ctrl-Z, then: kill -9 %1
terraform plan
terraform force-unlock <ID from the error>
terraform plan
```

A single Ctrl-C is a graceful shutdown that releases the lock, so the run uses `SIGKILL`. The
recorded run killed the apply after 25 seconds. The next plan fails with the same `Error acquiring
the state lock` and a new ID. `force-unlock` prints `Terraform state has been successfully
unlocked!`, and the plan after it prints `No changes.` **What to notice.** The lock outlived the
process that took it. `force-unlock` is correct when that process is dead. It is wrong when a
colleague's apply is still running, and nothing in the command can tell the difference. The `Who:`
and `Created:` fields exist so that a person can. Check them, message the person, and then unlock.

### Step 7 · Versioning is the undo

Someone at Queen City deletes the state object, and the company finds out what versioning bought it
in step 2.

```sh
gcloud storage rm gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  --project YOUR_PROJECT_ID
terraform plan
gcloud storage ls --all-versions --long \
  gs://dsba6190-tfstate-<SUFFIX>/envs/dev/ --project YOUR_PROJECT_ID
```

The plan proposes `Plan: 4 to add, 0 to change, 0 to destroy.` The listing shows nine
`default.tflock` generations and four `default.tfstate` generations. Read the byte counts rather
than the timestamps:

```
   180  ...  default.tfstate#1789046496243242
  4599  ...  default.tfstate#1789046497778916
  5111  ...  default.tfstate#1789046624708965
   180  ...  default.tfstate#1789046660262563
```

```sh
gcloud storage cp \
  "gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate#<GENERATION>" \
  gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  --project YOUR_PROJECT_ID
terraform plan
```

After the copy, the plan prints `No changes.` **What to notice.** Nothing in the project was
deleted. Terraform lost its record and proposed to build the estate a second time beside the one
that exists. The newest generation, 180 bytes, is the empty state written by the plan after the
deletion. The generation to restore is the 5,111-byte one from before the deletion. Versioning
restored the record. It restored no data, and it would not have helped if the buckets themselves had
been deleted. Step 11 makes that distinction concrete.

### Step 8 · Import what somebody built by hand

Queen City adopts the archive bucket and the cold-storage annex that someone created by hand, with
settings nobody wrote down. Look at both in the Console first.

```sh
cp legacy.tf.guess legacy.tf
cat legacy.tf
terraform import google_storage_bucket.legacy \
  YOUR_PROJECT_ID/dsba6190-legacy-<SUFFIX>
terraform plan
```

The block written from memory declares `location = "US-EAST1"`. The import prints `Import
successful!` The plan then proposes to replace the bucket, and it ends with `Plan: 1 to add, 0 to
change, 1 to destroy.` Do not apply it.

```
      ~ location                    = "US-CENTRAL1" -> "US-EAST1" # forces replacement
      ~ storage_class               = "NEARLINE" -> "STANDARD"
```

```sh
cp legacy.tf.matched legacy.tf
terraform plan
cp annex.tf.staged annex.tf
cat annex.tf
terraform plan
terraform apply
```

The matched configuration plans `0 to add, 1 to change, 0 to destroy`, a label diff. The annex plan
prints `Plan: 1 to import, 0 to add, 2 to change, 0 to destroy.` **What to notice.** Import needs an
address to attach to, and nothing checks that the block is right. The plan proposed to destroy the
bucket adopted seconds earlier, because import populates state, not configuration. The remaining
label diff is the provider adopting labels that Terraform did not set. The `import` block shows `1
to import` in a plan before anything happens, so a reviewer can read it on a pull request. A
command-line import has already run by the time anyone reads it. Terraform 1.5 requires a literal id
in an import block, so `annex.tf.staged` is a template. Terraform 1.6 lifts that restriction.

### Step 9 · Drift, and which side should win

An engineer on call edits a label on Queen City's trip bucket at 2 a.m. and tells nobody.

In the Cloud Console, open the raw bucket, edit its labels, change `owner` to `someone-at-2am`, and
save. The notebook makes the same edit with `gcloud storage buckets update --update-labels`.

```sh
terraform plan
terraform apply -refresh-only
terraform plan
```

The first plan shows `~ "owner" = "someone-at-2am" -> "data-platform"`. The refresh-only apply
reports `Objects have changed outside of Terraform` and records the new value in state without
changing any remote object. Answer `yes`. The plan after it proposes the same revert again. **What
to notice.** Terraform detected the drift on the next plan. It did not prevent it, and a scheduled
`plan` turns detection into an alert. The harder case is a change at 2 a.m. that was correct.
`-refresh-only` reconciles the record with reality and leaves the configuration unchanged. If
reality should win, change the configuration and send that change through review. If the
configuration should win, apply. No flag decides for you.

```sh
gcloud pubsub topics delete dsba6190-events-<SUFFIX> --project YOUR_PROJECT_ID
terraform plan
terraform apply
```

The plan proposes `Plan: 1 to add, 1 to change, 0 to destroy.` **What to notice.** One apply
reconciles both drifts, because both are the same operation: make reality match the configuration.

### Step 10 · Surgery on the record

Queen City hands the legacy archive back to manual management, then renames the trip bucket's
address without moving the bucket.

```sh
terraform state list
terraform state rm google_storage_bucket.legacy
terraform plan
rm legacy.tf
terraform plan
```

`state rm` prints `Successfully removed 1 resource instance(s).` The next plan proposes `1 to add`,
and the plan after `rm legacy.tf` prints `No changes.` **What to notice.** The bucket still exists.
Terraform forgot it and proposed to build a second bucket with the same name, which would fail. Once
the configuration also drops it, configuration and state agree that the bucket belongs to someone
else. That handover, to another configuration or to a team that manages it by hand, is the
legitimate use of `state rm`.

```sh
cp main.tf.renamed main.tf
terraform plan
terraform state mv google_storage_bucket.raw google_storage_bucket.landing
terraform plan
```

The first plan proposes `Plan: 1 to add, 0 to change, 1 to destroy.` `state mv` prints `Successfully
moved 1 object(s).` The last plan proposes no resource changes, only the output rename:

```
Changes to Outputs:
  + landing_bucket    = "gs://dsba6190-raw-<SUFFIX>"
  - raw_bucket        = "gs://dsba6190-raw-<SUFFIX>" -> null
```

**What to notice.** Only the resource's address changed, from `google_storage_bucket.raw` to
`google_storage_bucket.landing`. Terraform reads an unfamiliar address as a new resource and a
vanished one as a deletion. Session 3 showed that renaming a bucket's `name` forces replacement.
This is the other rename, and `state mv` avoids it. The safe rule is to change state through the
`terraform state` subcommands, never by editing the file.

### Step 11 · Refuse to destroy, then permit it

A fleet's quarterly totals land in Queen City's trip bucket, and nobody has another copy.

```sh
echo "quarterly totals, and nobody has a copy" > report.csv
gcloud storage cp report.csv gs://dsba6190-raw-<SUFFIX>/report.csv \
  --project YOUR_PROJECT_ID
cp main.tf.protected main.tf
terraform destroy
```

The plan counts `4 to destroy` and then fails:

```
Error: Instance cannot be destroyed

Resource google_storage_bucket.landing has lifecycle.prevent_destroy set, but
the plan calls for this resource to be destroyed.
```

```sh
cp main.tf.renamed main.tf
terraform destroy -target=google_storage_bucket.landing
```

This time the provider fails:

```
Error: Error trying to delete bucket dsba6190-raw-<SUFFIX> containing objects without `force_destroy` set to true
```

```sh
cp main.tf.forced main.tf
terraform apply
terraform destroy
```

The apply changes `force_destroy = false -> true`, and the destroy prints `Destroy complete!
Resources: 5 destroyed.` The file goes with the bucket. **What to notice.** `prevent_destroy` fails
the plan, so Terraform attempted nothing. Removing the `lifecycle` block is a diff a reviewer can
see. `force_destroy = false` is the provider refusing to delete a bucket that still holds objects.
Two mechanisms refuse at two different layers. `-target` isolates the failure to one bucket, and
Terraform warns that the flag is for recovering from errors, not routine use. Reverting the commit
would restore `force_destroy = false` and nothing else. Versioning restored the state record in step
7 and cannot restore this file. Infrastructure rollback is not a substitute for backups.

---

## Teardown

`terraform destroy` in step 11 removed everything Terraform manages. Two buckets remain on purpose.
The state bucket was created by hand in step 2, and the legacy bucket was handed back in step 10. If
you stopped before step 8, the annex bucket also remains, because nothing adopted it.

```sh
source ~/dsba6190-live-demo-04/env.sh
gcloud storage rm --recursive --all-versions "gs://${STATE_BUCKET:?}" --project "${PROJECT:?}"
gcloud storage rm --recursive "gs://${LEGACY_BUCKET:?}" --project "${PROJECT:?}"
gcloud storage rm --recursive "gs://${ANNEX_BUCKET:?}" --project "${PROJECT:?}"
gcloud storage ls --project "$PROJECT"
```

Every name is written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong
thing. `--all-versions` is required on the state bucket, because a bucket with noncurrent objects
will not delete. A 404 on any line means that resource was never created or was already removed. If
the demonstration ended before step 11, run `terraform destroy` in the working directory first. The
final listing returns `One or more URLs matched no objects.`

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `could not find default credentials` | Application default credentials expired. Run `gcloud auth application-default login` |
| `403 does not have storage.buckets.create` | The active project or account is wrong. Run `gcloud config set project YOUR_PROJECT_ID` |
| `bucket already exists` | A previous run holds the name. Re-run `live-setup.sh`, which derives a new suffix and re-applies the baseline in about ninety seconds |
| `Error acquiring the state lock` before step 5 | A previous run was killed and left a lock. Read the `Who:` and `Created:` fields, then run `terraform force-unlock -force <ID>` with the ID from the error |
| `Error: Backend configuration changed` | `backend.tf` was copied in before step 3. Delete `backend.tf`, keep `backend.tf.staged`, and run `terraform init -migrate-state` |
| `terraform init` refuses the migration | Read `capture/10-init-migrate.txt` through `capture/13-plan-no-changes.txt` and compare the backend block and bucket name |
| The import ID is rejected | The format is `<project>/<bucket>`. The bare bucket name also works |
| An `apply` hangs for more than two minutes | Press Ctrl-C once and compare with the matching file in `capture/` |
| The Pub/Sub topic will not recreate in step 9 | The name is still being released after the delete. Wait a minute and apply again |

---

## Files

| Path | What it is |
|---|---|
| `01-local-state/` to `06-destroy-controls/` | The baseline and each configuration variant the steps copy into place |
| `live-setup.sh` | Stages the working directory and applies the baseline. It never deletes anything |
| `capture.sh`, `capture/` | The recorder and its 51 output files, one per command |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
