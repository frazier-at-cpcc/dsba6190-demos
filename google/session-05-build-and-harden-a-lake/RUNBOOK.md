# Session 5 live demo · runbook

Build and harden a lake. One hour, twelve steps, 1:30 to 2:30 in the revised session plan.

Rehearsed end to end on 10 September 2026 against project `YOUR_PROJECT_ID`, Terraform v1.5.7,
`hashicorp/google` v5.45.2, Google Cloud SDK 584.0.0. Every command below was run. Every expected
output below is real, with one exception that is named as an exception in step 11.

**Do not run `capture.sh` in class.** It is the headless recorder. It uses `-auto-approve`, it makes
a bucket briefly public on purpose, it disables an encryption key on purpose, and it destroys
everything through an exit trap. `live-setup.sh` is its opposite.

> **Cost.** This demonstration is performed live in class on the instructor's billing account. It
> costs you nothing and you are not expected to run it. If you want to reproduce it on your own
> Google Cloud account, it costs **under $0.10**, which Google's $300 free credit for a
> new account covers many times over. Opening that account requires a credit card at signup, though
> Google does not charge it. That is your choice and no part of this course requires it.
> **Destroy what you create.** The teardown step is the last step for a reason.

The figure covers four Cloud Storage buckets holding about 17 MB for an hour, four BigQuery queries
reading 27 MB in total against a 1 TiB monthly free allowance, and one Cloud KMS key version. The
dominant line is the key version, which bills $0.06 per month and is the only charge that outlives
the evening. Storage and queries together are under a cent.

---

## The scenario · Catawba Precision Components

**Catawba Precision Components** is fictional: a precision-parts manufacturer with plants around
Charlotte. Every machine streams sensor readings to the data team, quality-control findings name the
plant, the part serial and the defect, and a regulator requires seven years of retention, immutable
for the first two. A5's industrial-monitoring company is this company at scale. The demonstration's
data is the company's data: `readings.csv` is plant telemetry, `qc.csv` is a quality-control
finding, and `_incident.csv` is a record the regulator requires Catawba to keep.

| Step | What it is in the scenario |
|---|---|
| 1 to 3 | Building Catawba's lake and its zones |
| 4 | An engineer makes the wrong bucket public to share a QC file with a supplier |
| 5 | A rerun overwrites the plant's reading manifest with a zero-row version |
| 6 | The plant managers' dashboard reads Parquet instead of CSV |
| 8 | The regulator's retention rule refuses a delete, even from the owner |
| 9 | Revoking the key makes the sensitive records unreadable |
| 10 | The dashboard asks for one day and reads one day |

Introduce the company on slide 32, in about two minutes. `demo.ipynb` holds every command on the
Bash kernel, converted from the step scripts in `steps/`.

---

## How the hour fits the session clock

The session plan carried this demonstration at thirteen minutes inside 1:10 to 1:50.

| Clock | Segment | Minutes |
|---|---|---|
| 0:00–0:10 | Retrieval warm-up | 10 |
| 0:10–0:55 | Concept Block 1 · Storage | 45 |
| 0:55–1:05 | Break | 10 |
| 1:05–1:30 | Concept Block 2 · Formats and governance | 25 |
| **1:30–2:30** | **This demonstration** | **60** |
| 2:30–2:55 | Guided lab · Lab 5, supervised start | 25 |
| 2:55–3:00 | Wrap | 5 |

Concept Block 1 loses five minutes. Concept Block 2 was forty minutes with a thirteen-minute
demonstration inside it and is now twenty-five minutes of concept with the demonstration lifted out.
The demonstration performs what the lost minutes would have described. Name each idea from the
slide, then let the terminal supply the evidence.

**The guided lab is now a supervised start rather than a completion window.** Lab 5 is the Badge 2
guided course and is submitted by Wednesday 23 September in any case. Twenty-five minutes buys the
first tasks in the room where help is available. Say that at 2:30, and give the retention warning
from the lab brief before anybody sets a policy rather than after.

---

## Before class

### T minus 30 minutes

```sh
cd "lectures/demos/session-05-build-and-harden-a-lake"
./live-setup.sh YOUR_PROJECT_ID ~/dsba6190-live-demo-05 86612
# Or directly from the step runner:
./steps/00-setup.sh
```

**This script applies.** It applies exactly one thing: the ungoverned bucket the demonstration
starts from. Step 2 adds the governed bucket beside it and step 4 runs the same command against
both, so the ungoverned one has to exist before the hour begins.

It also creates the Cloud KMS key ring, the key, a live key version, and the Cloud Storage service
agent's binding on that key. Those are out of band for two reasons. IAM propagation on a key takes
longer than step 9 has, and a key ring cannot be deleted once created, so it should not be a
resource Terraform believes it can remove.

It generates the sample data, because 200,000 rows of invented telemetry do not belong in a Git
repository. Generation is seeded, so the byte counts quoted below are the byte counts you will see.

The script prints the working directory, the name suffix (`86612`), every resource name, and the
three-line teardown. The default working directory is `~/dsba6190-live-demo-05`.

### T minus 25 minutes, verify

```sh
cd ~/dsba6190-live-demo-05
terraform plan
```

Expect `No changes. Your infrastructure matches the configuration.` Anything else means fix it now
rather than at 1:30.

Common causes, in the order they occur:

| Symptom | Cause | Fix |
|---|---|---|
| `could not find default credentials` | Application default credentials expired | `gcloud auth application-default login` |
| `403 does not have storage.buckets.create` | Wrong active project or account | `gcloud config set project YOUR_PROJECT_ID` |
| `bucket already exists` | A previous run left a name taken | Re-run `live-setup.sh`; it derives a new suffix |
| `Cloud KMS API has not been used in project` | The API was enabled seconds ago and has not propagated | Wait one minute and re-run `live-setup.sh` |
| `FAILED_PRECONDITION: key version is scheduled for destruction` | A teardown scheduled the version and the window closed | Re-run `live-setup.sh`; it creates a fresh primary version |
| `ModuleNotFoundError: No module named 'pyarrow'` | The sample generator has no Parquet writer | `python3 -m pip install pyarrow` |
| `Error 409: Already Exists: Dataset` | A previous demo's dataset survived teardown | `bq rm -r -f -d dsba6190_lake_86612` |
| The `dt=` prefixes are missing under `sample/events/` | The generator ran against a stale directory | `rm -rf ~/dsba6190-live-demo-05` and re-run `live-setup.sh` |

### Set up the room

- Terminal at a size the back row can read. Plan output and error text are the teaching material.
- Visual Studio Code open on `lectures/demos/session-05-build-and-harden-a-lake` (or `~/dsba6190-live-demo-05`), showing the `steps/` folder and `lake.tf.staged`.
- Browser tab on the Cloud Console, Cloud Storage, in the demo project. Steps 2, 4, 7 and 8 are
  better seen there.
- A second browser tab on the BigQuery console. Steps 6 and 10 read a byte count, and the Job
  Information panel shows it larger than the terminal does.
- Deck on slide 31, the Live Demonstration divider, with the Catawba Precision Components scenario on 32, the run sheet on 33 and 34, and the twelve capture slides at 35 to 46.

**Network contingency.** If the room has no working connection, present from the deck. Slides 30 to
41 carry one capture slide per step, trimmed to the type floor and drawn from the same outputs, and
the full text of every command is in `capture/`. Every file in it is real output from the 10
September rehearsal, one file per command, numbered in the order below. Say plainly that the run is
recorded rather than live. The repository standard is that a capture is labelled as one.

---

## The sequence

Every command is run from `~/dsba6190-live-demo-05`. `terraform.tfvars` is already written, so no
command needs a `-var` flag. The session suffix for this run is **`86612`**; the rehearsal captured
outputs below carry `65111`.

Each step leaves the precondition the next one needs. Do not reorder them.

### Running in Visual Studio Code

A dedicated `steps/` folder provides standalone, executable bash scripts for every step. Each script
runs inside `~/dsba6190-live-demo-05`, carries default environment variables for `YOUR_PROJECT_ID`
and suffix `86612`, and prints colorized step headers with the relevant teaching notes:

- **Run individual steps** from the VS Code integrated terminal (`Cmd+\`` / `Ctrl+\``):
  ```sh
  ./steps/01-read-plan.sh
  ./steps/02-apply-governed.sh
  ```
- **Run the interactive menu:**
  ```sh
  ./steps/menu.sh
  ```
- **VS Code Tasks:** Press `Cmd+Shift+P`, select **Tasks: Run Task**, and pick any demo step.

### Step 1 · Read the governed bucket before anything runs · slide 30 · 4 minutes

**Step script:** `./steps/01-read-plan.sh`

```sh
cp lake.tf.staged lake.tf
cat lake.tf
```

Read the resource argument by argument against the governance list from Concept Block 2. Four
controls are present: `uniform_bucket_level_access`, `public_access_prevention`, `versioning`, and
`labels`. Name what is absent: there is no `retention_policy` and no `lifecycle_rule`. Both arrive
later, at their own steps.

```sh
terraform plan
```

Expect `Plan: 1 to add, 0 to change, 0 to destroy.` and, inside the plan, the four controls printed
back as attributes:

```
      + location                    = "US-EAST1"
      + name                        = "dsba6190-lake-65111"
      + public_access_prevention    = "enforced"
      + storage_class               = "STANDARD"
      + uniform_bucket_level_access = true

      + versioning {
          + enabled = true
        }
```

**What to notice.** The plan is the review artifact. Every governance decision on slide 30 is
visible in it before anything exists, which is the argument A5 asks students to make about
enforcement rather than documentation. Ask the room which of the four controls they would fail a
pull request over.

### Step 2 · Apply. Two buckets, one governed · slide 30 · 5 minutes

**Step script:** `./steps/02-apply-governed.sh`

```sh
terraform apply
```

Expect `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.` and two outputs, because the
ungoverned bucket was there before the hour began.

```sh
gcloud storage buckets describe gs://dsba6190-lake-86612 \
  --project YOUR_PROJECT_ID \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"
```

Expect *(rehearsal output shows `65111`; in class expect `86612`)*:

```
default_storage_class: STANDARD
labels:
  course: dsba6190
  environment: demo
  owner: data-platform
  zone: lake
location: US-EAST1
name: dsba6190-lake-65111
public_access_prevention: enforced
uniform_bucket_level_access: true
versioning_enabled: true
```

Now the same command against the bucket nobody governed:

```sh
gcloud storage buckets describe gs://dsba6190-staging-86612 \
  --project YOUR_PROJECT_ID \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"
```

Expect:

```
default_storage_class: STANDARD
location: US-EAST1
name: dsba6190-staging-65111
public_access_prevention: inherited
uniform_bucket_level_access: false
versioning_enabled: false
```

**What to notice.** Read the two outputs side by side. The second bucket has no labels at all, which
means no cost attribution and no owner. `public_access_prevention: inherited` is the word Google
uses for a setting that comes from somewhere above the project, and nothing above this project sets
it, so inherited means off. Step 4 shows what that costs.

### Step 3 · The four zones, and the object that lands in raw · slide 12 · 4 minutes

**Step script:** `./steps/03-create-zones.sh`

```sh
for z in raw validated curated archive quarantine; do
  printf 'zone: %s\ncontract: see lecture 5, slide 12\n' "$z" > _zone.txt
  gcloud storage cp _zone.txt gs://dsba6190-lake-86612/$z/_ZONE \
    --project YOUR_PROJECT_ID
done

gcloud storage ls gs://dsba6190-lake-86612 --project YOUR_PROJECT_ID
```

Expect:

```
gs://dsba6190-lake-65111/archive/
gs://dsba6190-lake-65111/curated/
gs://dsba6190-lake-65111/quarantine/
gs://dsba6190-lake-65111/raw/
gs://dsba6190-lake-65111/validated/
```

**What to notice.** Five prefixes and zero directories. Creating a zone required writing an object,
because a prefix that contains nothing does not exist. This is slide 9 made concrete: the Console
draws a tree and Cloud Storage stores flat keys with slashes in them. Name each zone's contract out
loud, and name quarantine as the fifth thing that is not a zone and must exist anyway.

```sh
gcloud storage cp sample/readings.csv \
  gs://dsba6190-lake-86612/raw/readings/readings.csv \
  --project YOUR_PROJECT_ID

gcloud storage ls -r gs://dsba6190-lake-86612/raw/ --project YOUR_PROJECT_ID
```

Expect:

```
gs://dsba6190-lake-65111/raw/:
gs://dsba6190-lake-65111/raw/_ZONE

gs://dsba6190-lake-65111/raw/readings/:
gs://dsba6190-lake-65111/raw/readings/readings.csv
```

**What to notice.** 200,000 rows of industrial telemetry landed in Raw exactly as they arrived. Say
the Raw contract now, because steps 5, 8 and 12 are the mechanisms that enforce it.

### Step 4 · Make it public. Twice · slide 28 · 5 minutes

**Step script:** `./steps/04-test-public-refusals.sh`

Start with the bucket nobody governed.

```sh
gcloud storage buckets add-iam-policy-binding gs://dsba6190-staging-86612 \
  --project YOUR_PROJECT_ID \
  --member=allUsers --role=roles/storage.objectViewer
```

The command succeeds and prints the policy back, including:

```
- members:
  - allUsers
  role: roles/storage.objectViewer
```

Prove it is genuinely public, from outside any credential:

```sh
printf 'plant,serial,defect\ncharlotte,SN-88213,hairline crack\n' > _qc.csv
gcloud storage cp _qc.csv gs://dsba6190-staging-86612/qc.csv \
  --project YOUR_PROJECT_ID

curl https://storage.googleapis.com/dsba6190-staging-86612/qc.csv
```

Expect the file content, served to an anonymous request:

```
plant,serial,defect
charlotte,SN-88213,hairline crack
```

Now the same binding against the governed bucket:

```sh
gcloud storage buckets add-iam-policy-binding gs://dsba6190-lake-86612 \
  --project YOUR_PROJECT_ID \
  --member=allUsers --role=roles/storage.objectViewer
```

Expect a refusal:

```
ERROR: (gcloud.storage.buckets.add-iam-policy-binding) HTTPError 412: The member
bindings allUsers and allAuthenticatedUsers are not allowed since public access
prevention is enforced.
```

And the per-object route, which is the one Lab 5 warns about:

```sh
gcloud storage objects update gs://dsba6190-lake-86612/raw/readings/readings.csv \
  --project YOUR_PROJECT_ID \
  --add-acl-grant=entity=allUsers,role=READER
```

Expect a different refusal, from a different control:

```
ERROR: HTTPError 400: Cannot update access control for an object when uniform
bucket-level access is enabled. Read more at
https://cloud.google.com/storage/docs/uniform-bucket-level-access
```

Undo the exposure before moving on:

```sh
gcloud storage buckets remove-iam-policy-binding gs://dsba6190-staging-86612 \
  --project YOUR_PROJECT_ID \
  --member=allUsers --role=roles/storage.objectViewer
```

**What to notice.** Three outcomes, one command shape. The ungoverned bucket accepted the grant and
served the object to the open internet in under a second. Public access prevention returned `412`
and refused the binding. Uniform bucket-level access returned `400` and refused the per-object
route, which is the error the lab brief predicts students will meet without an explanation attached.
Say the distinction plainly: **public access prevention is a refusal, not a warning**, and the two
controls close different doors. Slide 28 asks for a principal, a role, and a level; `allUsers` at
bucket level is all three, and it is the one A5 marks down.

### Step 5 · Versioning is the undo · slide 25 · 6 minutes

**Step script:** `./steps/05-versioning-undo.sh`

```sh
printf '{"rows": 200000, "written_by": "nightly-ingest", "status": "complete"}\n' > _manifest.json
gcloud storage cp _manifest.json \
  gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID

gcloud storage objects describe \
  gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID --format='value(generation)'
```

Write that generation number down. It is the thing being restored.

Now the rerun nobody reviewed:

```sh
printf '{"rows": 0, "written_by": "the-rerun-nobody-reviewed", "status": "complete"}\n' > _manifest.json
gcloud storage cp _manifest.json \
  gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID

gcloud storage cat gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID
```

Expect `{"rows": 0, "written_by": "the-rerun-nobody-reviewed", "status": "complete"}`.

```sh
gcloud storage ls --all-versions --long \
  gs://dsba6190-lake-86612/raw/readings/ --project YOUR_PROJECT_ID
```

Expect both generations, and the CSV:

```
        71  2026-09-10T18:32:35Z  gs://dsba6190-lake-65111/raw/readings/_manifest.json#1789065155335817  metageneration=1
        77  2026-09-10T18:32:37Z  gs://dsba6190-lake-65111/raw/readings/_manifest.json#1789065157288197  metageneration=1
  12348336  2026-09-10T18:32:27Z  gs://dsba6190-lake-65111/raw/readings/readings.csv#1789065147093001  metageneration=1
TOTAL: 3 objects, 12348484 bytes (11.78MiB)
```

```sh
gcloud storage cp \
  "gs://dsba6190-lake-86612/raw/readings/_manifest.json#<GENERATION>" \
  gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID

gcloud storage cat gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID
```

Expect `{"rows": 200000, "written_by": "nightly-ingest", "status": "complete"}`.

Then do it again for a delete rather than an overwrite:

```sh
gcloud storage rm gs://dsba6190-lake-86612/raw/readings/_manifest.json \
  --project YOUR_PROJECT_ID

gcloud storage ls gs://dsba6190-lake-86612/raw/readings/ --project YOUR_PROJECT_ID
```

Expect only `readings.csv`. The manifest is gone.

```sh
gcloud storage ls --all-versions --long \
  gs://dsba6190-lake-86612/raw/readings/_manifest.json --project YOUR_PROJECT_ID
```

Expect three generations still listed. Restore the good one again with the same `cp`.

**What to notice.** The overwrite did not replace the object; it added a generation and moved the
pointer. The delete did not remove the bytes; it removed the live pointer. Versioning is the undo
for both, and `#<generation>` is the syntax that names a specific past. Then say the cost
consequence: every superseded generation is still stored and still billed, which is why a lifecycle
rule that expires noncurrent versions belongs on any versioned bucket that takes real traffic. That
rule is absent here on purpose. Ask the room to name it as a gap.

### Step 6 · CSV to Parquet. Two arguments, two numbers · slides 18 and 20 · 7 minutes

**Step script:** `./steps/06-compare-formats.sh`

```sh
gcloud storage cp sample/readings.parquet \
  gs://dsba6190-lake-86612/curated/readings/readings.parquet \
  --project YOUR_PROJECT_ID

gcloud storage ls -l \
  gs://dsba6190-lake-86612/raw/readings/readings.csv \
  gs://dsba6190-lake-86612/curated/readings/readings.parquet \
  --project YOUR_PROJECT_ID
```

Expect:

```
  12348336  2026-09-10T18:32:27Z  gs://dsba6190-lake-65111/raw/readings/readings.csv
TOTAL: 1 objects, 12348336 bytes (11.78MiB)
   2680274  2026-09-10T18:32:46Z  gs://dsba6190-lake-65111/curated/readings/readings.parquet
TOTAL: 1 objects, 2680274 bytes (2.56MiB)
```

**That is the storage argument: 11.78 MiB against 2.56 MiB, the same 200,000 rows, 4.6 times
smaller.** It is not the interesting number.

```sh
cp tables.tf.staged tables.tf
terraform apply
```

Expect `Apply complete! Resources: 3 added`. One dataset, two external tables over objects that are
already in the bucket. Nothing was copied into BigQuery.

```sh
bq query --use_legacy_sql=false --nouse_cache --job_id=dsba6190-86612-csv \
  'SELECT ROUND(AVG(value), 3) AS mean_reading
   FROM `YOUR_PROJECT_ID.dsba6190_lake_86612.readings_csv`'

bq query --use_legacy_sql=false --nouse_cache --job_id=dsba6190-86612-parq \
  'SELECT ROUND(AVG(value), 3) AS mean_reading
   FROM `YOUR_PROJECT_ID.dsba6190_lake_86612.readings_parquet`'
```

Both return the same answer:

```
+--------------+
| mean_reading |
+--------------+
|      119.799 |
+--------------+
```

Now read what each one cost:

```sh
bq show -j dsba6190-86612-csv
bq show -j dsba6190-86612-parq
```

Expect, in the `Bytes Processed` column:

| Job | Bytes Processed | Bytes Billed |
|---|---|---|
| `dsba6190-csv` | 12,348,283 | 12,582,912 |
| `dsba6190-parq` | **1,600,000** | 10,485,760 |

**What to notice.** Identical rows, identical answer, and BigQuery read 7.7 times fewer bytes from
the Parquet copy. Explain the second number rather than the first: 1,600,000 is exactly 200,000 rows
times eight bytes, which is the `value` column and nothing else. Columnar storage let the engine
skip five of the six columns without decompressing them. The CSV table had no such option, because a
row format must read every byte of every row to reach one field.

Then read the `Bytes Billed` column and be honest about it. BigQuery bills a **10 MB minimum per
table scanned**, so at this size the cheaper query is billed more than it read. The ratio is the
lesson, not the invoice. At A5's stated volume of 120 GB a day the minimum disappears and the ratio
is the whole cost. This is the connection to Week 7 and Week 14: **format is not performance tuning,
it is cost control.**

### Step 7 · The lifecycle rule that nothing runs tonight · slide 11 · 4 minutes

**Step script:** `./steps/07-apply-lifecycle.sh`

```sh
cp lake.tf.lifecycle lake.tf
terraform plan
```

Expect `Plan: 0 to add, 1 to change, 0 to destroy.` and an in-place update whose entire diff is the
two blocks added:

```
  ~ resource "google_storage_bucket" "lake" {
        id                          = "dsba6190-lake-65111"
        # (15 unchanged attributes hidden)

      + lifecycle_rule {
          + action {
              + storage_class = "NEARLINE"
              + type          = "SetStorageClass"
            }
          + condition {
              + age                   = 30
            }
        }
      + lifecycle_rule {
          + action {
              + storage_class = "ARCHIVE"
              + type          = "SetStorageClass"
            }
          + condition {
              + age                   = 365
            }
        }
    }
```

```sh
terraform apply

gcloud storage buckets describe gs://dsba6190-lake-86612 \
  --project YOUR_PROJECT_ID --format="yaml(name,lifecycle_config)"
```

Expect:

```
lifecycle_config:
  rule:
  - action:
      storageClass: NEARLINE
      type: SetStorageClass
    condition:
      age: 30
  - action:
      storageClass: ARCHIVE
      type: SetStorageClass
    condition:
      age: 365
name: dsba6190-lake-65111
```

**What to notice.** Say plainly that **nothing moves tonight**. Cloud Storage evaluates lifecycle
rules asynchronously, roughly once a day, and every object in this bucket was written minutes ago.
The rule is the artifact. Then make the two points slide 11 carries. The rule encodes an
access-pattern decision, so a rule that moves weekly-read data to Coldline costs more than leaving
it in Standard. And a rule whose action is `Delete` is a retention policy expressed in code and also
a way to destroy evidence somebody was legally required to keep, which is why deletion rules deserve
the review a production deploy gets. There is no `Delete` rule here on purpose.

### Step 8 · Retention, and a delete that fails · slides 14 and 24 · 5 minutes

**Step script:** `./steps/08-retention-refusal.sh`

```sh
cp vault.tf.staged vault.tf
terraform apply
```

Expect `Apply complete! Resources: 1 added`.

```sh
gcloud storage buckets describe gs://dsba6190-vault-86612 \
  --project YOUR_PROJECT_ID --format="yaml(name,retention_policy)"
```

Expect:

```
name: dsba6190-vault-65111
retention_policy:
  effectiveTime: '2026-09-10T18:33:11.232000+00:00'
  retentionPeriod: '3600'
```

```sh
printf 'incident,plant,reading,recorded_at\n1,charlotte,231.4,2026-09-17T19:04:11Z\n' > _incident.csv
gcloud storage cp _incident.csv gs://dsba6190-vault-86612/raw/incident.csv \
  --project YOUR_PROJECT_ID

gcloud storage rm gs://dsba6190-vault-86612/raw/incident.csv \
  --project YOUR_PROJECT_ID
```

Expect a refusal:

```
ERROR: HTTPError 403: Object 'dsba6190-vault-65111/raw/incident.csv' is subject to
bucket's retention policy or object retention and cannot be deleted or overwritten
until 2026-09-10T12:33:11.232127-07:00.
```

**What to notice.** This is the seam A5 grades. The Raw zone's Immutable contract was stated in
Concept Block 1 as a sentence and it is a `retention_policy` here. Read the error's last clause
aloud: the object cannot be deleted **or overwritten**, and the refusal applies to the account that
wrote it.

Then show where Bucket Lock is, in the Console, on the bucket's Protection tab, **and do not click
it.** Say the three consequences in order: locking makes the retention period permanent, permanent
includes against you, and a locked bucket cannot be deleted until every object has met its retention
period. One hour is set here rather than the seven years on slide 30 for exactly that reason, and
step 12 is where it matters.

### Step 9 · CMEK, and crypto-shredding · slide 24 · 7 minutes

**Step script:** `./steps/09-cmek-crypto-shredding.sh`

```sh
cp secure.tf.staged secure.tf
terraform apply
```

Expect `Apply complete! Resources: 1 added`.

```sh
printf 'patient_site,serial,defect\ncharlotte,SN-88213,hairline crack\n' > _regulated.csv
gcloud storage cp _regulated.csv gs://dsba6190-secure-86612/raw/regulated.csv \
  --project YOUR_PROJECT_ID

gcloud storage objects describe gs://dsba6190-secure-86612/raw/regulated.csv \
  --project YOUR_PROJECT_ID --format="yaml(name,kms_key)"
```

Expect the key version that encrypted the object:

```
kms_key: projects/YOUR_PROJECT_ID/locations/us-east1/keyRings/dsba6190-demo/cryptoKeys/lake-cmek/cryptoKeyVersions/1
name: raw/regulated.csv
```

```sh
gcloud storage cat gs://dsba6190-secure-86612/raw/regulated.csv \
  --project YOUR_PROJECT_ID
```

Expect the content. Now destroy the ability to read it, without touching the object:

```sh
gcloud kms keys versions disable 1 --key lake-cmek --keyring dsba6190-demo \
  --location us-east1 --project YOUR_PROJECT_ID
```

Expect `state: DISABLED`. Then read again:

```sh
gcloud storage cat gs://dsba6190-secure-86612/raw/regulated.csv \
  --project YOUR_PROJECT_ID
```

Expect:

```
ERROR: (gcloud.storage.cat) HTTPError 400: Cloud KMS key is disabled, destroyed, or
scheduled to be destroyed.
- '@type': type.googleapis.com/google.rpc.PreconditionFailure
  violations:
  - description: ''
    subject: ''
    type: KEY_DISABLED
```

**The refusal is not always immediate.** The rehearsal saw it within seconds; an earlier run was
still serving the object ten seconds after the disable. Cloud Storage can answer a read from a
cached unwrapped key for a short while. If the first read succeeds, say so, keep talking through the
argument below, and run it again. Writing is refused on the same schedule and is worth showing once
the refusal has arrived:

```sh
gcloud storage cp _regulated.csv gs://dsba6190-secure-86612/raw/second.csv \
  --project YOUR_PROJECT_ID
```

Expect the same `KEY_DISABLED` violation.

Put it back:

```sh
gcloud kms keys versions enable 1 --key lake-cmek --keyring dsba6190-demo \
  --location us-east1 --project YOUR_PROJECT_ID

gcloud storage cat gs://dsba6190-secure-86612/raw/regulated.csv \
  --project YOUR_PROJECT_ID
```

Expect the content back.

**What to notice.** Nothing happened to the object. It was encrypted before this step and it is
encrypted now, and slide 24's point is that CMEK did not add encryption. What changed is who holds
the key, and that is worth exactly one thing: the ability to make ciphertext permanently unreadable
without finding every copy of it. Name the two sides. **Crypto-shredding** is a faster and more
provable deletion than a delete sweep across an unknown number of replicas and backups. It is also
the failure mode: `disable` was reversible here, `destroy` is not, and losing the key loses the
data. Then say what this costs to leave running. A key version bills $0.06 per month for as long as
it exists, and the key ring cannot be deleted at all.

### Step 10 · Partition pruning, measured · slide 15 · 6 minutes

**Step script:** `./steps/10-partition-pruning.sh`

```sh
gcloud storage cp -r sample/events gs://dsba6190-lake-86612/curated/ \
  --project YOUR_PROJECT_ID

gcloud storage ls gs://dsba6190-lake-86612/curated/events/ \
  --project YOUR_PROJECT_ID
```

Expect ten prefixes, ending on the session's own date:

```
gs://dsba6190-lake-65111/curated/events/dt=2026-09-08/
...
gs://dsba6190-lake-65111/curated/events/dt=2026-09-17/
```

```sh
cp events.tf.staged events.tf
cat events.tf
terraform apply
```

Read `hive_partitioning_options` aloud before applying. `mode = "AUTO"` and `source_uri_prefix`
pointing at the directory *above* `dt=` are the whole configuration.

```sh
bq query --use_legacy_sql=false --nouse_cache --job_id=dsba6190-86612-all \
  'SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading
   FROM `YOUR_PROJECT_ID.dsba6190_lake_86612.events`'

bq query --use_legacy_sql=false --nouse_cache --job_id=dsba6190-86612-one \
  'SELECT COUNT(*) AS readings, ROUND(AVG(value), 3) AS mean_reading
   FROM `YOUR_PROJECT_ID.dsba6190_lake_86612.events`
   WHERE dt = "2026-09-17"'
```

Expect 200,000 rows and then 20,000 rows.

```sh
bq show -j dsba6190-86612-all
bq show -j dsba6190-86612-one
```

| Job | Rows | Bytes Processed |
|---|---|---|
| `dsba6190-86612-all` | 200,000 | 1,600,000 |
| `dsba6190-86612-one` | 20,000 | **160,000** |

**What to notice.** Exactly ten times fewer bytes, from a `WHERE` clause on a column that does not
exist in any file. `dt` is a directory name. BigQuery read the prefix list, matched one, and never
opened the other nine objects. Say the two payoffs slide 15 names and connect each to A5. Partition
pruning is the difference between scanning a day and scanning a decade, which at 120 GB a day is the
difference between a query that costs cents and one that costs dollars. Idempotent writes mean
reprocessing 17 September overwrites one prefix and leaves the other nine alone, which is what makes
the Raw zone's reprocess-from-source promise operational rather than aspirational.

Then give the sizing heuristic against what is on screen. These ten objects are about 200 KB each,
far below the 128 MB to 1 GB target, and at real volume that is the small files problem returning in
Week 10 as a Spark pathology.

### Step 11 · The guardrail above the project · slide 28 · 3 minutes · **capture step**

**Step script:** `./steps/11-check-org-policy.sh`

**This is the one step that is not performed live, and the reason is worth the ninety seconds it
takes to say.** Public access prevention was set on a bucket in step 2, and a bucket setting is a
setting somebody with bucket permissions can change back. The guardrail version of the same control
is an Organization Policy set above the project, on the organization or a folder, which no project
owner can override.

```sh
gcloud projects get-ancestors YOUR_PROJECT_ID
```

Expect:

```
ID                    TYPE
YOUR_PROJECT_ID  project
```

```sh
gcloud organizations list
gcloud org-policies list --project=YOUR_PROJECT_ID
```

Both expect `Listed 0 items.`

```sh
gcloud org-policies describe constraints/storage.publicAccessPrevention \
  --project=YOUR_PROJECT_ID --effective
```

Expect:

```
name: projects/PROJECT_NUMBER/policies/storage.publicAccessPrevention
spec:
  rules:
  - enforce: false
```

And the attempt to set it:

```
ERROR: (gcloud.org-policies.set-policy) Permission 'orgpolicy.policies.create' denied
on resource '//cloudresourcemanager.googleapis.com/projects/YOUR_PROJECT_ID'
```

**What to notice.** `get-ancestors` returns one row, and that row is the project itself. This
project has no organization and no folder above it, so there is nothing to attach an organization
policy to and `orgpolicy.policyAdmin` is a role that cannot be held here. Every command above is
real output from the 10 September rehearsal. **The one thing this course cannot show you is an
enforced policy, because the course does not own an organization.** Say that in those words rather
than presenting a picture of one.

Then finish the argument with what the lab brief already tells them: an organization-level public
access prevention policy overrides the bucket setting, so a Lab 5 step that fails to make something
public is usually working as intended. That sentence is the only encounter most students will have
with this control, and it is worth knowing that the thing refusing them sits above the project they
can see.

**Deck note.** `capture/53-project-ancestors.txt` through `capture/57-org-policy-set-refused.txt`
carry these five outputs. Four of them are authored onto slide 45, which is titled as a capture and
carries the same sentence in its speaker notes.

### Step 12 · Teardown is a teaching step · slide 25 · 4 minutes

**Step script:** `./steps/12-teardown.sh`

```sh
terraform destroy
```

Expect `Plan: 0 to add, 0 to change, 8 to destroy.`, then most of the estate going, and then a
failure:

```
google_storage_bucket.secure: Destruction complete after 1s
google_bigquery_dataset.lake: Destruction complete after 1s
google_storage_bucket.lake: Destruction complete after 1s

Error: could not delete non-empty bucket due to error when deleting contents:
googleapi: Error 403: Object 'dsba6190-vault-65111/raw/incident.csv' is subject to
bucket's retention policy or object retention and cannot be deleted or overwritten
until 2026-09-10T12:33:11.232127-07:00, retentionPolicyNotMet
```

```sh
gcloud storage buckets update gs://dsba6190-vault-86612 \
  --project YOUR_PROJECT_ID --clear-retention-period

terraform destroy
```

Expect `Destroy complete! Resources: 1 destroyed.`

**What to notice.** Three things, in this order.

The retention policy worked. It refused Terraform exactly as it refused the interactive `rm` in step
8, which is the difference between a control and a convention.

The destroy was not atomic. Seven resources are gone and one is not, and Terraform did not roll the
seven back. A failed apply leaves a partial estate, and the record of what happened is state rather
than the configuration.

The policy could be cleared because it was never locked. **Bucket Lock would have made this
impossible**, and the bucket would have stayed in the project until every object met its retention
period. Ask what would have happened with the seven years on slide 30 and a locked policy. Let the
answer land.

**End here.** The last thing on screen is a destroy that had to be argued with. Say that A5 asks for
retention policies *and* recovery procedures, and that this step is where those two requirements
meet: the control that protects the data from you is the same control that stops you cleaning up,
and a design that does not plan for its own teardown is not finished. Then move to the lab at 2:30.

---

## Teardown

Run this the same evening. Not tomorrow.

- [ ] **Destroy by the mechanism that created it.** `terraform destroy` for anything Terraform built.
      A resource deleted in the Console but left in state produces a plan next week that nobody
      expects. Step 12 performs this in front of the room. If the demonstration stopped earlier, run
      the two lines `live-setup.sh` printed, in that order: clear the retention period first, then
      destroy.
- [ ] ~~**Compute.** No cluster, instance, node pool, or worker remains.~~ This demonstration
      provisions no compute.
- [ ] ~~**Streaming.** Every Dataflow job drained or cancelled, every feeding Cloud Scheduler job
      deleted or paused.~~ No streaming resource is created.
- [ ] ~~**Serving.** Every Vertex AI endpoint undeployed.~~ No serving resource is created.
- [ ] ~~**Managed services with an hourly floor.** Data Fusion, Composer, Dataproc.~~ None is used.
- [ ] ~~**Networking.** Forwarding rules, static external IPs, Cloud NAT gateways.~~ Nothing here has
      a network endpoint.
- [ ] **Storage.** Four demo buckets deleted: `dsba6190-staging-86612`, `dsba6190-lake-86612`,
      `dsba6190-vault-86612`, `dsba6190-secure-86612`. **The retention policy on the vault
      bucket is removed *before* the delete is attempted, or the delete fails and looks like a
      permissions problem.** Confirm with `gcloud storage ls --project YOUR_PROJECT_ID`, which
      should answer `One or more URLs matched no objects.`
- [ ] **Public access.** Confirm the `allUsers` binding from step 4 is gone. Step 4 removes it, and
      the check is one command:
      `gcloud projects get-iam-policy YOUR_PROJECT_ID --format=json | grep allUsers`
      should return nothing. Deleting the bucket removes the binding with it in any case.
- [ ] **Keys.** Schedule the Cloud KMS key version for destruction:
      `gcloud kms keys versions destroy 1 --key lake-cmek --keyring dsba6190-demo --location us-east1 --project YOUR_PROJECT_ID`.
      **The key ring and the key cannot be deleted and will remain visible in the project
      permanently.** `live-setup.sh` reuses them and restores or replaces the version on the next run.
      A scheduled version still bills until it is destroyed. The window on `lake-cmek` in
      `YOUR_PROJECT_ID` is Google's default of 30 days, because the key was created on
      10 September before `live-setup.sh` carried `--destroy-scheduled-duration=24h`, and that
      setting cannot be changed after a key exists. The script now creates keys with the 24-hour
      minimum, so a different project gets the shorter window. The difference is about five cents
      across the term and is not worth a second undeletable key.
- [ ] **BigQuery.** Dataset `dsba6190_lake_86612` dropped. `terraform destroy` does this, because
      the dataset carries `delete_contents_on_destroy = true`. Confirm with
      `bq --project_id=YOUR_PROJECT_ID ls`, which should list only `analytics_demo`, a
      pre-existing dataset this demonstration does not touch.
- [ ] ~~**Registry.** Demo images deleted from Artifact Registry.~~ No image is built.
- [ ] **Verify against billing, next morning.** Billing → Reports, filtered to the demo project,
      grouped by service, for yesterday. Confirm the charge matches what this runbook predicted, and
      write the actual figure into the cost line above. A predicted number that is never checked is
      an estimate forever. Expect three lines: Cloud Storage at a fraction of a cent, BigQuery at
      zero against the free allowance, and Cloud KMS at $0.06 prorated.
- [ ] **Budget alert still armed.** Confirm the project budget and its alert threshold are unchanged.
- [ ] **Anything that could not be destroyed** is written here, with the reason and a date to revisit.
      As of 10 September 2026 that list is: the Cloud KMS key ring `dsba6190-demo` and the key
      `lake-cmek`, which Google does not permit deleting; and four enabled APIs, `storage`,
      `bigquery`, `cloudkms` and `orgpolicy`, which are free to leave on and which `live-setup.sh`
      expects.

---

## If it fails live

| What happened | Do this |
|---|---|
| `apply` hangs longer than about two minutes | Ctrl-C once, then present the matching file from `capture/`. Every line in it is real output from the 10 September rehearsal |
| The public fetch in step 4 returns `AccessDenied` | The binding has not propagated. Wait fifteen seconds and re-run the `curl`. The refusals that follow it do not depend on it |
| The `KEY_DISABLED` read in step 9 does not refuse | A cached key is still serving the read. Keep talking, run it again after twenty seconds, and show the write refusal instead if it still succeeds |
| `bq show -j` reports a job id already exists | A previous run used the same name. Append the suffix: `--job_id=dsba6190-86612-csv-rerun` |
| `Bytes Processed` reads `0` | The job was answered from cache. Re-run the query with `--nouse_cache`, which every command above already carries |
| The external table returns `Not found: URI` | The Parquet upload in step 6 or step 10 did not finish. Re-run the `gcloud storage cp` and then `terraform apply` |
| Credentials expired mid-session | Do not debug in front of the room. Move to `capture/` and say the run is recorded |
| A bucket name collides | Re-run `live-setup.sh` for a new suffix. This costs about sixty seconds because it regenerates the sample data |
| The step 12 destroy succeeds on the first attempt | The retention period expired, which means more than an hour passed since step 8. Say so, and present `capture/58-destroy-refused.txt` for the refusal |

The captured output is not a lesser version of this demonstration. It is the same run, recorded on
10 September 2026, and every line is real. Switching to it costs the room nothing except the sight
of a command being typed.

---

## What is staged where

`live-setup.sh` writes all of these into the working directory before class. Terraform reads every
`.tf` file in a directory, so adding a staged file is the whole edit and the plan that follows shows
exactly one change.

| Path | Step | What it is |
|---|---|---|
| `main.tf` | baseline | Providers, variables, and the ungoverned bucket step 4 compares against |
| `terraform.tfvars` | all | Project, name suffix, region and key name, so no command needs a flag |
| `lake.tf.staged` | 1 and 2 | The governed bucket, with four of the five controls |
| `tables.tf.staged` | 6 | The dataset and the CSV and Parquet external tables |
| `lake.tf.lifecycle` | 7 | The same bucket, plus the two `lifecycle_rule` blocks |
| `vault.tf.staged` | 8 | The bucket with a one-hour `retention_policy` |
| `secure.tf.staged` | 9 | The CMEK bucket, pointing at the key `live-setup.sh` created |
| `events.tf.staged` | 10 | The external table with `hive_partitioning_options` |
| `sample/readings.csv` | 3 and 6 | 200,000 rows, 12,348,336 bytes |
| `sample/readings.parquet` | 6 | The same rows, 2,680,274 bytes |
| `sample/events/dt=…` | 10 | Ten daily prefixes, 20,000 rows each |
| `steps/00-setup.sh` .. `12-teardown.sh` | all | Executable bash scripts for each step in Visual Studio Code |
| `steps/menu.sh` | all | Interactive terminal menu for stepping through the live demo |
| `.vscode/tasks.json` | all | VS Code tasks integration to run steps directly via command palette |

**Two things are deliberately not Terraform's.** The Cloud KMS key ring and key are created by
`live-setup.sh` because a key ring cannot be deleted and Terraform should not manage a resource it
cannot remove. The zone prefixes are created by `gcloud` in step 3 because a prefix is an object,
not a resource, and pretending otherwise would teach the wrong model of object storage.

---

## Where the captured output is on the deck

Slides 33 and 34 carry the twelve-step run sheet with its minute budgets. Slides 35 to 46 carry one
capture slide per step, each one a listing of real output trimmed to render at 28px or larger, with
the capture date and the source directory named in its speaker notes. Step 11's slide is titled as a
capture, because it is the one step that is not performed live.

| Step | Deck slide | Captures authored onto it |
|---|---|---|
| 1 | 35 | `02-plan-governed.txt` |
| 2 | 36 | `04-lake-controls.txt`, `05-staging-controls.txt` |
| 3 | 37 | `06-create-zones.txt`, `08-list-zones.txt` |
| 4 | 38 | `10-public-object-fetched.txt`, `11-public-refused-lake.txt`, `12-acl-refused-lake.txt` |
| 5 | 39 | `15-manifest-overwritten.txt`, `16-all-versions.txt`, `18-manifest-restored.txt`, `21-versions-survive-delete.txt` |
| 6 | 40 | `24-object-sizes.txt`, `26-query-csv.txt`, `27-bytes-csv.txt`, `29-bytes-parquet.txt` |
| 7 | 41 | `32-lifecycle-in-place.txt` |
| 8 | 42 | `34-retention-policy.txt`, `36-delete-refused.txt` |
| 9 | 43 | `41-disable-key-version.txt`, `42-read-key-disabled.txt`, `44-enable-key-version.txt` |
| 10 | 44 | `47-list-partitions.txt`, `49` through `52` |
| 11 | 45 | `53-project-ancestors.txt`, `54`, `56`, `57-org-policy-set-refused.txt` |
| 12 | 46 | `58-destroy-refused.txt`, `60-destroy-succeeds.txt` |

The masked values stay masked. `capture.sh` replaces the authenticated account with
`instructor@example.edu` and the project number with `PROJECT_NUMBER`, and the deck carries them in
that form.

**The numbers above are counted from the built PDF, not from the AsciiDoc headings.** The converter
inserts nothing into this deck, because Session 5 now carries an authored `== Agenda` slide, but
three slides split in two when a table and a figure share a heading.
