# Session 4 live demo · runbook

Migrate state, then break it. One hour, eleven steps, 1:00 to 2:00 in the revised session plan.

Rehearsed end to end on 10 September 2026 against project `YOUR_PROJECT_ID`, Terraform v1.5.7,
`hashicorp/google` v5.45.2, `hashicorp/random` v3.9.0, `hashicorp/time` v0.14.1. Every command below
was run; every expected output below is real.

**Do not run `capture.sh` in class.** It is the headless recorder. It uses `-auto-approve`, it kills
a running apply on purpose, it prints nothing worth watching, and it destroys everything through an
exit trap. `live-setup.sh` is its opposite.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you want to reproduce it on your own
> Google Cloud account, it costs **under $0.05**, which Google's $300 free credit for a
> new account covers many times over. Opening that account requires a credit card at signup, though
> Google does not charge it. That is your choice and no part of this course requires it.
> **Destroy what you create.** The teardown step is the last step for a reason.

The figure covers four Cloud Storage buckets, one Pub/Sub topic and a few kilobytes of objects,
living for about an hour. The dominant line is the state bucket, because versioning keeps every
generation and the demonstration writes state twenty times.

---

## The scenario · Queen City Trip Analytics

The hour is taught as one company's first month with shared state, so that students watch each
control protect a business rather than a demonstration estate. **Queen City Trip Analytics** is
fictional: a twelve-person analytics firm in South End, Charlotte, that sells trip-demand dashboards
to ground-transportation fleets. In Session 3 it codified its nightly-trips bucket with Terraform,
on one engineer's laptop.

Tonight is month one. A second engineer joins, and state that lives on one laptop becomes the
company's largest risk. The company moves its state to a shared, versioned, locked backend before
anything else breaks, and then meets each failure that backend exists to survive. No resource and no
command changes for the scenario. The table names what each resource is to the company.

| Demo resource | What it is in the scenario |
|---|---|
| `google_storage_bucket.raw`, `dsba6190-raw-<SUFFIX>` | The trip bucket, where fleets drop their nightly trip files |
| `google_pubsub_topic.events`, `dsba6190-events-<SUFFIX>` | The topic that carries trip events to the dashboards |
| `random_password.db_admin` | The admin credential for the dashboard database. Terraform generated it, so Terraform stores it, and that is why state is sensitive |
| `dsba6190-tfstate-<SUFFIX>`, created by hand in step 2 | The shared state bucket both engineers use from tonight on |
| `google_storage_bucket.legacy`, `dsba6190-legacy-<SUFFIX>` | An archive bucket someone created by hand in the Console before the company adopted Terraform. Nobody wrote down its settings |
| `google_storage_bucket.annex`, `dsba6190-annex-<SUFFIX>` | A cold-storage annex made the same way, which the company adopts through a reviewed `import` block |
| `time_sleep.slow_apply` | It has no business meaning. It holds an apply open long enough for the room to see the lock |
| The second terminal in steps 5 and 6 | The engineer who joined this month |
| `report.csv` in step 11 | A fleet customer's quarterly totals, of which nobody has a copy |

| Step | What the company is doing |
|---|---|
| 1 | The founding engineer reads the state on the laptop and finds the database credential in plain text |
| 2 | The company builds the bucket its state will share before the new engineer runs anything |
| 3 | The company moves its state off the laptop and into that bucket, and the credential moves with it |
| 4 | The company confirms that the estate did not change, then deletes the copies left on the laptop |
| 5 | Both engineers run Terraform at once, and the lock makes the new engineer wait |
| 6 | An apply on one laptop dies mid-run and leaves its lock behind |
| 7 | Someone deletes the state object, and a prior generation restores the company's record |
| 8 | The company adopts the two buckets that predate its use of Terraform |
| 9 | An engineer on call changes a label on the trip bucket at 2 a.m., and someone deletes the trip-event topic |
| 10 | The company hands the legacy archive back to manual management and renames the trip bucket's address |
| 11 | A fleet's quarterly totals land in the trip bucket, and two controls refuse to destroy it |

**One honesty note, say it at step 1.** The estate holds no real trips. The trip bucket stays empty
until step 11 writes one file, and the password protects no database. The scenario names what each
resource would be at the company.

Introduce the company on the scenario slide, slide 28, in about two minutes. Then open each step
with one sentence of what the company is doing. Each step below begins with that sentence, and the
slide notes carry it too.

---

## How the hour fits the session clock

The session plan carried this demonstration at fifteen minutes inside 1:10 to 1:50.

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:08 | Retrieval warm-up | 8 |
| 0:08–0:40 | Concept Block 1 · State | 32 |
| 0:40–0:50 | Concept Block 2 · Delivery | 10 |
| 0:50–1:00 | Break | 10 |
| **1:00–2:00** | **This demonstration** | **60** |
| 2:00–2:52 | Guided lab · Lab 4 | 52 |
| 2:52–3:00 | Wrap | 8 |

Concept Block 1 loses eighteen minutes and Concept Block 2 loses fifteen. The demonstration performs
what those minutes would have described: the sensitivity of state, the local-to-remote migration,
locking, import, secrets, rollback and destructive-change prevention are all executed rather than
asserted. Name each idea from the slide, then let the terminal supply the evidence.

The lab keeps fifty-two minutes, which was never enough and is not meant to be. Google lists Lab 4
at fifteen minutes; the honest figure is an hour. Task 1 happens in the room where help is available
and Task 2 is finished before Wednesday. Say that at 2:00.

---

## Before class

Drive the hour from `demo.ipynb` on the Bash kernel: VS Code, Select Kernel, Jupyter Kernel, Bash.

### T minus 30 minutes

```sh
cd "lectures/demos/session-04-migrate-state-then-break-it"
./live-setup.sh YOUR_PROJECT_ID
```

**Unlike Session 3, this script applies.** The demonstration begins from an estate that already
exists on local state, so the setup builds that estate with the local backend. It also creates two
buckets by hand, because steps 8 and 10 need resources Terraform did not build and a bucket made ten
seconds ago is not legacy. It deliberately does **not** create the state bucket. Creating the state
bucket is step 2.

The script prints the working directory, the name suffix, every bucket name, and the three-line
teardown. Note the suffix. The default working directory is `~/dsba6190-live-demo-04`.

### T minus 25 minutes, verify

```sh
cd ~/dsba6190-live-demo-04
terraform plan
```

Expect `No changes. Your infrastructure matches the configuration.` Anything else means fix it now
rather than at 1:00.

Common causes, in the order they occur:

| Symptom | Cause | Fix |
|---|---|---|
| `could not find default credentials` | Application default credentials expired | `gcloud auth application-default login` |
| `403 does not have storage.buckets.create` | Wrong active project or account | `gcloud config set project YOUR_PROJECT_ID` |
| `bucket already exists` | A previous run left a name taken | Re-run `live-setup.sh`; it derives a new suffix |
| `Error acquiring the state lock` before step 5 | A previous run was killed and left a lock | `terraform force-unlock -force <ID>`, using the ID in the error |
| `Error: Backend configuration changed` | `backend.tf` was copied in before class | Delete `backend.tf`, keep `backend.tf.staged`, run `terraform init -migrate-state` |
| Pub/Sub topic slow to create | The name was recently deleted and is being released | Wait. It takes up to a minute and resolves itself |

### Set up the room

- Terminal at a size the back row can read. Plan output is the teaching material.
- **A second terminal, already in `~/dsba6190-live-demo-04`.** Step 5 needs it and there is no time
  to open one.
- Editor open on `~/dsba6190-live-demo-04/main.tf`.
- Browser tab on the Cloud Console, Cloud Storage, in the demo project. Steps 2, 3, 8 and 9 are
  better seen there.
- Deck on slide 9. The scenario slide is 28, the run sheet is slides 29 and 30, and the captured
  output runs from slide 31 to slide 41, one slide per step.

**Network contingency.** If the room has no working connection, advance to the capture slides.
Slides 31 to 41 carry a trimmed capture for each step and the full files are in `capture/`, one file
per command, numbered in the order below. Every line is real output from the 10 September rehearsal.
Say plainly that the run is recorded rather than live. The repository standard is that a capture is
labelled as one.

---

## The sequence

Every command is run from `~/dsba6190-live-demo-04`. `terraform.tfvars` is already written, so no
command needs a `-var` flag.

Each step leaves the precondition the next one needs. Do not reorder them.

### Step 1 · Read the state you already have · slide 9 · 6 minutes

Queen City's state lives on one laptop, the founding engineer's, and tonight a second engineer needs
it.

```sh
terraform state list
```

Expect three addresses:

```
google_pubsub_topic.events
google_storage_bucket.raw
random_password.db_admin
```

**What to notice.** This is what Terraform believes it manages. Not what exists in the project, and
not what is in the configuration. A third thing.

```sh
terraform output
```

Expect `db_admin_password = <sensitive>`.

```sh
terraform state show random_password.db_admin
```

Expect `result = (sensitive value)`.

**What to notice.** Two commands have now refused to show you the password. Ask the room whether the
value is protected. Do not answer.

```sh
grep -o '"result": "[^"]*"' terraform.tfstate
```

Expect the password, in full, in plain text.

**What to notice.** `sensitive = true` suppresses the console and does nothing to the file. The file
is on the laptop, next to the configuration, one `git add .` away from a public repository. This is
the security point from slide 9, and it is the reason the next step exists.

### Step 2 · Bootstrap the state bucket, with versioning · slide 10 · 5 minutes

Before the new engineer runs anything, Queen City builds the bucket its state will share.

```sh
gcloud storage buckets create gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID --location=US-EAST1 \
  --uniform-bucket-level-access --public-access-prevention

gcloud storage buckets update gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID --versioning
```

```sh
gcloud storage buckets describe gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"
```

Expect:

```
default_storage_class: STANDARD
location: US-EAST1
name: dsba6190-tfstate-<SUFFIX>
public_access_prevention: enforced
uniform_bucket_level_access: true
versioning_enabled: true
```

**What to notice.** Three of slide 10's four controls are in that output. Uniform access removes the
per-object escape hatch, public access prevention makes the bucket un-shareable by accident, and
versioning is the undo that step 7 uses. The fourth control, Data Access audit logging, is a project
setting rather than a bucket setting; name it and move on.

Say why this is done by hand: `terraform init` will refuse to configure a backend whose bucket does
not exist, and a configuration cannot create the bucket its own state lives in. That is the
chicken-and-egg the guided lab's watch-for names.

### Step 3 · The backend block, and the migration · slide 14 · 6 minutes

Queen City moves its state off the laptop and into the shared bucket, and the dashboard database
credential moves with it.

```sh
cp backend.tf.staged backend.tf
cat backend.tf
```

Read the block aloud. `bucket` names the state bucket. `prefix` is `envs/dev`, which is what lets
one bucket hold several environments as separate objects.

**What to notice.** The staged file is a template that `live-setup.sh` filled in, because **a
backend block may not contain a variable.** That restriction is slide 14's watch-for. In a real
repository the answer is partial configuration plus `-backend-config` on the command line.

```sh
terraform init -migrate-state
```

Answer `yes` at the prompt. Expect:

```
Initializing the backend...

Successfully configured the backend "gcs"! Terraform will automatically
use this backend unless the backend configuration changes.
```

**Never answer `no` here, and never reach for `-reconfigure` instead.** Either one initializes the
new backend with an empty state, leaves the local file unread, and makes the next `plan` propose to
build the entire estate a second time alongside the one that already exists.

```sh
gcloud storage ls -r gs://dsba6190-tfstate-<SUFFIX>
```

Expect `gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate`.

```sh
gcloud storage cat gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  | grep -o '"result": "[^"]*"'
```

Expect the same password string from step 1.

**What to notice.** This is the payoff for the whole first hour. The state bucket is now a secret
store, and every control in step 2 is protecting a credential rather than a configuration file. Say
that the IAM policy on this bucket is a production access-control decision, not housekeeping.

### Step 4 · Plan says no changes · slide 14 · 3 minutes

Queen City confirms that moving the record changed nothing in its estate, then cleans the laptop.

```sh
terraform plan
```

Expect `No changes. Your infrastructure matches the configuration.`

**What to notice.** The record moved. Reality did not. That sentence is the point of the migration,
and it is what Lab 4 never asks students to check, which is why the lab brief tells them to run it
themselves.

```sh
ls -l terraform.tfstate*
grep -o '"result": "[^"]*"' terraform.tfstate.backup
```

Expect a zero-byte `terraform.tfstate`, a `terraform.tfstate.backup` of about 4.6 KB, and the
password still in the backup.

**What to notice.** Migration cleaned up nothing. The secret is still on the laptop in a file whose
name is not the one anybody thinks to check. Delete both, in the room:

```sh
rm terraform.tfstate terraform.tfstate.backup
```

### Step 5 · Two terminals, one lock · slide 13 · 6 minutes

Both Queen City engineers run Terraform against the same estate at the same moment. The first
terminal is the founding engineer and the second is the engineer who joined this month.

```sh
cp main.tf.sleep main.tf
```

Show the addition. `time_sleep` costs nothing and blocks the apply for ninety seconds, which is the
only reason the lock is visible at all.

**First terminal:**

```sh
terraform apply
```

Answer `yes`. While it runs, switch.

**Second terminal:**

```sh
terraform plan
```

Expect:

```
Error: Error acquiring the state lock

Error message: writing "gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tflock"
failed: googleapi: Error 412: At least one of the pre-conditions you
specified did not hold., conditionNotMet
Lock Info:
  ID:        1789046532656217
  Path:      gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tflock
  Operation: OperationTypeApply
  Who:       instructor@laptop.local
  Version:   1.5.7
  Created:   2026-09-10 13:22:12.550084 +0000 UTC
```

**What to notice.** Read the `Lock Info` block line by line. It names who holds the lock, which
operation they are running, and when they took it. Then point at the mechanism: a `.tflock` object
and HTTP 412, which is an object-generation precondition. No lock table, no extra infrastructure.

Then read the last line of the error aloud, the one offering `-lock=false`, and say that it is there
because the tool cannot stop you and that using it is how the corruption on slide 11 happens.

Let the first terminal finish before moving on.

### Step 6 · The crashed run, and `force-unlock` · slide 12 · 4 minutes

An apply on one Queen City laptop dies mid-run, and the lock it took stays behind. Locking has a
failure mode, and it is the one students meet first.

**First terminal:**

```sh
terraform apply -replace=time_sleep.slow_apply
```

Answer `yes`. Wait about twenty seconds, then kill it hard: **Ctrl-Z, then `kill -9 %1`.** A single
Ctrl-C is a graceful shutdown and releases the lock, which is not the failure being demonstrated.

```sh
terraform plan
```

Expect the same `Error acquiring the state lock`, with a new ID.

**What to notice.** The lock outlived the process that took it. Nobody is applying. The estate is
unreachable until somebody clears it.

```sh
terraform force-unlock <ID from the error>
```

Expect `Terraform state has been successfully unlocked!`

```sh
terraform plan
```

Expect `No changes.`

**What to notice.** State this precisely, because it is the sentence students misremember.
`force-unlock` is correct when the process that took the lock is dead. It is wrong when a
colleague's apply is still running, and there is nothing in the command that can tell the
difference. The `Who:` and `Created:` fields exist so a human can. Check them, then message the
person, then unlock.

### Step 7 · Versioning is the undo · slide 10 · 5 minutes

Someone at Queen City deletes the state object, and the company finds out what versioning bought it
in step 2.

```sh
gcloud storage rm gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  --project YOUR_PROJECT_ID
```

```sh
terraform plan
```

Expect `Plan: 4 to add, 0 to change, 0 to destroy.`

**What to notice.** Stop and let this sit. Nothing was deleted from the project. Every bucket and
the topic are still there. Terraform lost its record and now proposes to build the estate a second
time next to the one that already exists. This is the state-loss scenario from slide 7, on screen,
caused by deleting one object.

```sh
gcloud storage ls --all-versions --long \
  gs://dsba6190-tfstate-<SUFFIX>/envs/dev/ --project YOUR_PROJECT_ID
```

Expect several `default.tflock` generations and four `default.tfstate` generations. Read the byte
counts rather than the timestamps:

```
   180  ...  default.tfstate#1789046496243242
  4599  ...  default.tfstate#1789046497778916
  5111  ...  default.tfstate#1789046624708965
   180  ...  default.tfstate#1789046660262563
```

**What to notice.** The newest generation is 180 bytes, and it is the empty state written by the
plan you ran a moment ago. The one you want is the 5111-byte generation from before the deletion.
Point at both.

```sh
gcloud storage cp \
  "gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate#<GENERATION>" \
  gs://dsba6190-tfstate-<SUFFIX>/envs/dev/default.tfstate \
  --project YOUR_PROJECT_ID
```

```sh
terraform plan
```

Expect `No changes. Your infrastructure matches the configuration.`

**What to notice.** This is the whole argument for versioning on the state bucket, and it is worth
one sentence of qualification: versioning restored the **record**. It restored no data, and it would
not have helped if the buckets themselves had been deleted. That distinction is the rollback answer
A4 is graded on, and step 11 makes it concrete.

### Step 8 · Import what somebody built by hand · slides 16 and 17 · 9 minutes

Queen City adopts the archive bucket and the cold-storage annex that someone created by hand before
the company used Terraform. Two buckets in this project were created before class, out of band, with
settings nobody wrote down. Show them in the Console. This is what inheriting an estate looks like.

```sh
cp legacy.tf.guess legacy.tf
cat legacy.tf
```

**What to notice.** The block is written from memory and it is wrong. Import needs an address to
attach to, so a block has to exist first, and nothing checks that it is right.

```sh
terraform import google_storage_bucket.legacy \
  YOUR_PROJECT_ID/dsba6190-legacy-<SUFFIX>
```

Expect `Import successful!`

**Say this out loud.** Lab 4 runs this against a Docker container. This is the same command against
Google Cloud, and the resource type students will search for is `google_storage_bucket`.

```sh
terraform plan
```

Expect `-/+ destroy and then create replacement`, with `# forces replacement` on the location line,
and `Plan: 1 to add, 0 to change, 1 to destroy.`

```
      ~ location                    = "US-CENTRAL1" -> "US-EAST1" # forces replacement
      ~ storage_class               = "NEARLINE" -> "STANDARD"
```

**Stop here and do not apply.** The plan is proposing to destroy the bucket that was adopted thirty
seconds ago, because the configuration says `US-EAST1` and the bucket is in `US-CENTRAL1`. This is
slide 15's sentence made visible: **import populates state, not configuration.** It is also the same
`# forces replacement` string from Session 3, which is worth naming.

```sh
cp legacy.tf.matched legacy.tf
terraform plan
```

Expect `Plan: 0 to add, 1 to change, 0 to destroy.` and a label diff.

**What to notice.** No longer destructive, and not yet empty. The residue is instructive: the
provider tracks which labels Terraform set separately from labels that already existed, so the first
apply adopts them. This is the iteration slide 16 describes, and each pass is the estate documenting
itself.

```sh
cp annex.tf.staged annex.tf
cat annex.tf
terraform plan
```

Expect `Plan: 1 to import, 0 to add, 2 to change, 0 to destroy.`

**What to notice.** `1 to import`, in a plan, before anything happened. That is the difference the
deck claims on slide 15 and it is the reason `import` blocks exist: a command-line import cannot be
reviewed on a pull request, because by the time anyone reads it, it has already run. Tie it to slide
21's approval gate.

```sh
terraform apply
```

### Step 9 · Drift, and which side should win · slide 21 · 6 minutes

An engineer on call edits a label on Queen City's trip bucket at 2 a.m. and tells nobody.

In the **Cloud Console**, open the raw bucket, edit its labels, and change `owner` to
`someone-at-2am`. Save. Doing it in the Console is the point. A person changed something outside
Terraform and told nobody.

```sh
terraform plan
```

Expect `~ "owner" = "someone-at-2am" -> "data-platform"` and `Plan: 0 to add, 1 to change, 0 to
destroy.`

**What to notice.** Terraform found it on the next plan. Detection, not prevention. Slide 21 names
the scheduled `plan` that turns this into an alert.

Then put the harder case to the room and let them answer it: what if the person at 2am was right?

```sh
terraform apply -refresh-only
```

Expect `Note: Objects have changed outside of Terraform`, the same label diff in the other
direction, and:

```
This is a refresh-only plan, so Terraform will not take any actions to undo
these. If you were expecting these changes then you can apply this plan to
record the updated values in the Terraform state without changing any remote
objects.
```

Answer `yes`.

```sh
terraform plan
```

Expect the revert **again**: `~ "owner" = "someone-at-2am" -> "data-platform"`.

**What to notice.** This is the correction worth the whole step. `-refresh-only` reconciles the
record with reality. It does not change what you asked for. If reality should win, the configuration
has to change and that change goes through review. If the configuration should win, apply. There is
no third option, and no flag that decides for you.

Then the coarser drift:

```sh
gcloud pubsub topics delete dsba6190-events-<SUFFIX> --project YOUR_PROJECT_ID
terraform plan
```

Expect `Plan: 1 to add, 1 to change, 0 to destroy.`

```sh
terraform apply
```

**What to notice.** One apply reconciles both drifts, because both are the same operation: make
reality match the configuration.

### Step 10 · Surgery on the record · slide 50 · 5 minutes

Queen City hands the legacy archive back to manual management, then renames the trip bucket's
address without moving the bucket.

```sh
terraform state list
terraform state rm google_storage_bucket.legacy
```

Expect `Removed google_storage_bucket.legacy` and `Successfully removed 1 resource instance(s).`

```sh
terraform plan
```

Expect `Plan: 1 to add, 0 to change, 0 to destroy.`

**What to notice.** The bucket still exists. Terraform has forgotten it, and now proposes to build a
second one with the same name, which would fail. Forgetting is not free.

```sh
rm legacy.tf
terraform plan
```

Expect `No changes.`

**What to notice.** Configuration and state now agree that this bucket is not Terraform's problem.
It is somebody's problem. That is what `state rm` is for and it is the honest use of it: handing a
resource to another configuration, or to a team that manages it by hand.

Then the refactor, which is the Session 3 callback:

```sh
cp main.tf.renamed main.tf
terraform plan
```

Expect `Plan: 1 to add, 0 to change, 1 to destroy.`

**What to notice.** Nothing about the bucket changed. Only its **address** in the configuration
changed, from `google_storage_bucket.raw` to `google_storage_bucket.landing`. Terraform reads an
unfamiliar address as a new resource and a familiar one that vanished as a deletion. Session 3
showed that renaming the bucket's `name` forces replacement; this is the other rename, and it is
avoidable.

```sh
terraform state mv google_storage_bucket.raw google_storage_bucket.landing
```

Expect:

```
Move "google_storage_bucket.raw" to "google_storage_bucket.landing"
Successfully moved 1 object(s).
```

```sh
terraform plan
```

Expect no resource changes at all, and only the output rename:

```
Changes to Outputs:
  + landing_bucket    = "gs://dsba6190-raw-<SUFFIX>"
  - raw_bucket        = "gs://dsba6190-raw-<SUFFIX>" -> null

You can apply this plan to save these new output values to the Terraform
state, without changing any real infrastructure.
```

**What to notice.** Read the last sentence of that output aloud. The resource never moved, and the
plan that a minute ago proposed to destroy and rebuild a bucket now proposes nothing. The record was
told the new address. Name this as the tool for the module refactor A3 asked for, and as the reason
slide 50's rule is *use the `terraform state` subcommands* rather than *never touch state*.

### Step 11 · Refuse to destroy, then permit it · slide 25 · 5 minutes

A fleet's quarterly totals land in Queen City's trip bucket, and nobody has another copy.

```sh
echo "quarterly totals, and nobody has a copy" > report.csv
gcloud storage cp report.csv gs://dsba6190-raw-<SUFFIX>/report.csv \
  --project YOUR_PROJECT_ID
```

Data arrived. Terraform did not put it there and does not know about it.

```sh
cp main.tf.protected main.tf
terraform destroy
```

Expect `Plan: 0 to add, 0 to change, 4 to destroy.` and then a plan-time failure:

```
Error: Instance cannot be destroyed

  on main.tf line 45:
  45: resource "google_storage_bucket" "landing" {

Resource google_storage_bucket.landing has lifecycle.prevent_destroy set, but
the plan calls for this resource to be destroyed. To avoid this error and
continue with the plan, either disable lifecycle.prevent_destroy or reduce
the scope of the plan using the -target flag.
```

**What to notice.** Terraform planned four destroys and then refused all of them. Nothing was
attempted, because `prevent_destroy` fails the plan rather than the apply. Read the last sentence
and say that this is a guardrail rather than a lock: it stops the accident, and removing the
`lifecycle` block is a diff a reviewer can see.

```sh
cp main.tf.renamed main.tf
terraform destroy -target=google_storage_bucket.landing
```

Expect:

```
Error: Error trying to delete bucket dsba6190-raw-<SUFFIX> containing objects
without `force_destroy` set to true
```

**What to notice.** The second control, and a different refusal at a different layer.
`prevent_destroy` is Terraform refusing to plan the delete. `force_destroy = false` is the provider
refusing to perform it while the bucket still holds objects. Two mechanisms, and A4's eighth
requirement asks for the specific ones rather than the word.

`-target` is used here so the failure is isolated to the bucket. Terraform prints its own warning
about the flag, which is worth reading aloud: it is for recovering from errors, not for routine use.

```sh
cp main.tf.forced main.tf
terraform apply
```

Expect `~ force_destroy = false -> true`.

```sh
terraform destroy
```

Expect `Destroy complete! Resources: 5 destroyed.` Everything goes, including `report.csv`.

**End here.** Ask what would restore that file. Reverting the commit restores `force_destroy =
false` and restores nothing else. Versioning on the state bucket restored the record in step 7 and
would not have restored this. **Infrastructure rollback is not a substitute for backups**, and that
sentence is the trap A4's brief warns about. Let the silence run, then move to the lab.

---

## After class

`terraform destroy` in step 11 already removed everything Terraform manages. Two things remain, on
purpose:

```sh
gcloud storage rm --recursive --all-versions gs://dsba6190-tfstate-<SUFFIX> \
  --project YOUR_PROJECT_ID

gcloud storage rm --recursive gs://dsba6190-legacy-<SUFFIX> \
  --project YOUR_PROJECT_ID
```

The state bucket was created by hand in step 2 and no configuration manages it. The legacy bucket
was handed back to the humans in step 10. `--all-versions` is required on the state bucket because
versioning kept every generation and a bucket with noncurrent objects will not delete.

**If the demonstration stopped before step 8**, the annex bucket is also still there, because
nothing adopted it. Run the fourth line `live-setup.sh` printed:

```sh
gcloud storage rm --recursive gs://dsba6190-annex-<SUFFIX> \
  --project YOUR_PROJECT_ID
```

A 404 on any of these lines means that step never ran and there is nothing to remove.

Confirm nothing is left:

```sh
gcloud storage ls --project YOUR_PROJECT_ID
```

Expect `One or more URLs matched no objects.`

Run all four lines whenever the demonstration ended anywhere other than the end of step 11. Empty
buckets cost effectively nothing, but leaving them costs the next run its bucket names.

---

## If it fails live

| What happened | Do this |
|---|---|
| `apply` hangs longer than about two minutes | Ctrl-C once, then present the matching file from `capture/`. Every line in it is real output from the 10 September rehearsal |
| `Error acquiring the state lock` when you did not expect it | Read the `Who:` and `Created:` fields aloud, then `terraform force-unlock -force <ID>`. This is step 6 arriving early; teach it rather than hiding it |
| `terraform init` refuses the migration | Do not debug the backend in front of the room. Present `capture/10-init-migrate.txt` through `capture/13-plan-no-changes.txt` and continue from step 5 |
| The import ID is rejected | The format is `<project>/<bucket>`. The bare bucket name also works. Both are in `capture/27-import-cli.txt` |
| The Pub/Sub topic will not recreate in step 9 | The name is still being released after the delete. Wait a minute, or skip the apply and continue to step 10 |
| Credentials expired mid-session | Do not debug in front of the room. Move to `capture/` and say the run is recorded |
| A bucket name collides | Re-run `live-setup.sh` for a new suffix. This costs about ninety seconds because it re-applies the baseline |

The captured output is not a lesser version of this demonstration. It is the same run, recorded on
10 September 2026, and every line is real. Switching to it costs the room nothing except the sight
of a command being typed.

---

## What is staged where

`live-setup.sh` writes all of these into the working directory before class.

| Path | Step | What it is |
|---|---|---|
| `main.tf` | 1 | The baseline: a bucket, a topic, a generated password |
| `terraform.tfvars` | all | Project and name suffix, so no command needs a flag |
| `backend.tf.staged` | 3 | The `backend "gcs"` block with the bucket name filled in |
| `main.tf.sleep` | 5 | Adds `time_sleep`, which holds the lock for ninety seconds |
| `legacy.tf.guess` | 8 | The configuration written from memory, which is wrong |
| `legacy.tf.matched` | 8 | The configuration the plan asked for |
| `annex.tf.staged` | 8 | The plannable `import` block with the id filled in |
| `main.tf.renamed` | 10 | The bucket's address changed to `landing` |
| `main.tf.protected` | 11 | `prevent_destroy` on the bucket |
| `main.tf.forced` | 11 | `force_destroy = true` on the bucket |

Two of them are templates rather than configuration, because **a `backend` block may not contain a
variable and, in Terraform 1.5, neither may the `id` of an `import` block.** Terraform 1.6 lifts the
second restriction. Both are worth naming out loud when the file is opened, because both are the
kind of constraint students meet on their own and read as a mistake.

---

## Where the captured output is on the deck

The deck carries the demonstration. Slide 28 introduces Queen City Trip Analytics, slides 29 and 30
list the eleven steps with their minute budgets, and slides 31 to 41 carry one trimmed capture each,
in step order. Every line on them is real output from the 10 September 2026 rehearsal, and each
slide's speaker notes name the capture date and the source files. They do not replace performing the
demonstration. They are the projected output so the room can read what the terminal shows, and the
fallback if the network fails.

| Step | Deck slide | Captures on it |
|---|---|---|
| 1 | 31 | `02-output-redacted`, `03-state-show-redacted`, `05-password-in-plain-text` |
| 2 | 32 | `08-state-bucket-controls` |
| 3 | 33 | `10-init-migrate`, `11-state-object-in-bucket`, `12-password-in-the-bucket` |
| 4 | 34 | `13-plan-no-changes`, `14-local-copy-left-behind` |
| 5 | 35 | `16-lock-refused` |
| 6 | 36 | `18-stale-lock`, `19-force-unlock` |
| 7 | 37 | `22-plan-with-no-state`, `23-generations` |
| 8 | 38 | `28-plan-after-import`, `31-plan-import-block` |
| 9 | 39 | `35-refresh-only`, `36-plan-still-drifted` |
| 10 | 40 | `44-plan-address-change`, `45-state-mv`, `46-plan-after-mv` |
| 11 | 41 | `48-prevent-destroy`, `49-bucket-not-empty` |

Each block was trimmed to hold its longest line at 14pt or larger, which is the deck framework's
floor for a listing. The generated password is masked on the slides exactly as it is masked in
`capture/`. It is live on screen in the room, which is where the point lands.
