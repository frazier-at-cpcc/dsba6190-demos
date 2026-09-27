# Session 5 walkthrough · Build and harden a lake

This walkthrough builds a governed data lake on Cloud Storage in twelve steps and then tests each
control by trying to break it. It uses Terraform, Cloud Storage, BigQuery external tables and Cloud
KMS, all in `us-east1`. Every command below was run end to end on 10 September 2026 with Terraform
v1.5.7, the `hashicorp/google` provider v5.45.2 and Google Cloud SDK 584.0.0, and `capture/` holds
the full output of each one. You can read the walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under $0.10. Four buckets held about 17 MB for about fifteen
> minutes, and four measured queries read 27 MB against BigQuery's 1 TiB monthly free allowance. The
> largest charge is the Cloud KMS key version at $0.06 per month, which bills until it is destroyed.
> Delete what you create, in the order step 12 and the teardown section show.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Catawba Precision Components

**Catawba Precision Components** is a fictional precision-parts manufacturer with plants around
Charlotte. Every machine streams sensor readings to the data team. Quality-control findings name the
plant, the part serial and the defect. A regulator requires seven years of retention for incident
records. In the demonstration, `readings.csv` is plant telemetry, `qc.csv` is a quality-control
finding, and `incident.csv` is a record the regulator requires Catawba to keep.

| Step | What it is in the scenario |
|---|---|
| 1 to 3 | Building Catawba's lake and its zones |
| 4 | An engineer makes the wrong bucket public to share a QC file with a supplier |
| 5 | A rerun overwrites the plant's reading manifest with a zero-row version |
| 6 | The plant managers' dashboard reads Parquet instead of CSV |
| 8 | The regulator's retention rule refuses a delete, even from the owner |
| 9 | Revoking the key makes the sensitive records unreadable |
| 10 | The dashboard asks for one day and reads one day |

---

## Before you start

You need the Google Cloud CLI with `bq`, Terraform 1.5 or later, `curl`, and Python 3 with
`pyarrow`. If `pyarrow` is missing, `live-setup.sh` runs the generator through `uv` instead. You
need the Owner role on your project, because the setup enables APIs, creates a key and grants a
service agent access to it. Terraform uses application default credentials, so run `gcloud auth
application-default login` once.

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-05/env.sh
terraform plan                           # No changes. Your infrastructure matches the configuration.
```

The script enables four APIs: `storage`, `bigquery`, `cloudkms` and `orgpolicy`. It creates the
Cloud KMS key ring `dsba6190-demo` and the key `lake-cmek` in `us-east1`, and it grants the Cloud
Storage service agent use of the key. It generates the seeded sample data and writes a fresh working
directory, `~/dsba6190-live-demo-05`. It applies exactly one resource, the ungoverned bucket
`dsba6190-staging-<suffix>`, because step 4 compares against it. `env.sh` exports `PROJECT`,
`SUFFIX` and `WORK` and changes into the working directory.

Bucket names are global. The default suffix is `86612`, and the recorded outputs below carry
`65111`. If a name is taken, pass five digits of your own as the third argument: `./live-setup.sh
YOUR_PROJECT_ID ~/dsba6190-live-demo-05 40417`.

The Cloud KMS API takes about a minute to propagate after it is first enabled, and the grant on the
key takes a little longer. Run the setup a few minutes before you start. Generating the sample data
takes about a minute.

The key ring and the key are created outside Terraform on purpose. Google does not permit deleting a
key ring, so Terraform should not manage a resource it cannot remove. The zone prefixes in step 3
are created with `gcloud`, because a prefix is an object rather than a resource.

Each stage is a staged file that the step copies into place. Terraform reads every `.tf` file in the
directory, so the copy is the whole edit and the plan that follows shows exactly one change.

| Staged file | Step | What it adds |
|---|---|---|
| `lake.tf.staged` | 1 and 2 | The governed bucket |
| `tables.tf.staged` | 6 | The dataset and the CSV and Parquet external tables |
| `lake.tf.lifecycle` | 7 | The same bucket, plus two `lifecycle_rule` blocks |
| `vault.tf.staged` | 8 | A bucket with a one-hour `retention_policy` |
| `secure.tf.staged` | 9 | A bucket encrypted with the customer-managed key |
| `events.tf.staged` | 10 | An external table with `hive_partitioning_options` |

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. The same commands are in `steps/`, one script per step, and `./steps/menu.sh`
runs them from a menu. The step scripts apply with `-auto-approve`, so read the plan in step 1
before you run step 2. Run the steps in order, because each one leaves the precondition the next one
needs.

---

## The sequence

| # | Step |
|---|---|
| 1 | Read the governed bucket before anything runs |
| 2 | Apply. Two buckets, one governed |
| 3 | The four zones, and the object that lands in raw |
| 4 | Make it public. Twice |
| 5 | Versioning is the undo |
| 6 | CSV to Parquet. Two arguments, two numbers |
| 7 | The lifecycle rule that nothing runs tonight |
| 8 | Retention, and a delete that fails |
| 9 | CMEK, and crypto-shredding |
| 10 | Partition pruning, measured |
| 11 | The guardrail above the project |
| 12 | Teardown is a teaching step |

### Step 1 · Read the governed bucket before anything runs

```sh
cp lake.tf.staged lake.tf
cat lake.tf
terraform plan
```

The file declares four controls: `uniform_bucket_level_access`, `public_access_prevention`,
`versioning` and `labels`. The plan ends with `Plan: 1 to add, 0 to change, 0 to destroy.` and
prints each control back as an attribute:

```
      + public_access_prevention    = "enforced"
      + uniform_bucket_level_access = true
      + versioning {
          + enabled = true
        }
```

**What to notice.** The plan is the review artifact. Every governance decision is visible in it
before anything exists. A `retention_policy` and a `lifecycle_rule` are absent, and each arrives at
its own step. Decide which of the four controls you would reject a pull request over.

### Step 2 · Apply. Two buckets, one governed

`terraform apply` reports `Resources: 1 added` and two outputs, because the ungoverned bucket
already exists. Then describe both buckets with the same command:

```sh
gcloud storage buckets describe "gs://dsba6190-lake-$SUFFIX" --project "$PROJECT" \
  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention,labels)"
```

```
labels:
  course: dsba6190
  environment: demo
  owner: data-platform
  zone: lake
name: dsba6190-lake-65111
public_access_prevention: enforced
uniform_bucket_level_access: true
versioning_enabled: true
```

The same command against `dsba6190-staging-$SUFFIX` returns `public_access_prevention: inherited`,
`uniform_bucket_level_access: false`, and no labels or versioning line at all.

**What to notice.** The ungoverned bucket has no labels, so it has no cost attribution and no owner.
`inherited` means the setting comes from above the project. Nothing above this project sets it, so
`inherited` means off. Step 4 shows what that costs.

### Step 3 · The four zones, and the object that lands in raw

The step writes a small `_ZONE` marker object into each of five prefixes, `raw`, `validated`,
`curated`, `archive` and `quarantine`, and lists the bucket. It then uploads the telemetry into Raw:

```sh
gcloud storage cp sample/readings.csv "gs://dsba6190-lake-$SUFFIX/raw/readings/readings.csv" --project "$PROJECT"
gcloud storage ls -r "gs://dsba6190-lake-$SUFFIX/raw/" --project "$PROJECT"
```

The listing shows five prefixes, then `raw/_ZONE` and `raw/readings/readings.csv`.

**What to notice.** The bucket holds five prefixes and zero directories. Creating a zone required
writing an object, because a prefix that contains nothing does not exist. The Console draws a tree,
and Cloud Storage stores flat keys with slashes in them. Quarantine is not a zone, and the lake
needs it anyway. The 200,000 rows landed in Raw exactly as they arrived. Steps 5, 8 and 12 show the
mechanisms that keep Raw immutable.

### Step 4 · Make it public. Twice

```sh
gcloud storage buckets add-iam-policy-binding "gs://dsba6190-staging-$SUFFIX" --project "$PROJECT" \
  --member=allUsers --role=roles/storage.objectViewer
curl "https://storage.googleapis.com/dsba6190-staging-$SUFFIX/qc.csv"
```

The ungoverned bucket accepts the binding, and `curl`, with no credentials, returns the QC file:

```
plant,serial,defect
charlotte,SN-88213,hairline crack
```

The same binding against the governed bucket fails:

```
ERROR: (gcloud.storage.buckets.add-iam-policy-binding) HTTPError 412: The member bindings allUsers
and allAuthenticatedUsers are not allowed since public access prevention is enforced.
```

A per-object grant, `gcloud storage objects update ... --add-acl-grant=entity=allUsers,role=READER`,
fails with a different error, `HTTPError 400: Cannot update access control for an object when
uniform bucket-level access is enabled`. The step ends by removing the `allUsers` binding from the
ungoverned bucket.

**What to notice.** One command shape produced three outcomes. The ungoverned bucket served the file
to the open internet. Public access prevention returned `412` and refused the binding. Uniform
bucket-level access returned `400` and refused the per-object route. Public access prevention is a
refusal, not a warning, and the two controls close different doors. A grant to `allUsers` at bucket
level names a principal, a role and a level, and all three are wrong here.

### Step 5 · Versioning is the undo

The step writes a manifest that records 200,000 rows and saves its generation number. A second
write, `"written_by": "the-rerun-nobody-reviewed"`, overwrites it with `"rows": 0`. The listing then
shows both generations:

```sh
gcloud storage ls --all-versions --long "gs://dsba6190-lake-$SUFFIX/raw/readings/" --project "$PROJECT"
```

```
        71  2026-09-10T18:32:35Z  gs://dsba6190-lake-65111/raw/readings/_manifest.json#1789065155335817
        77  2026-09-10T18:32:37Z  gs://dsba6190-lake-65111/raw/readings/_manifest.json#1789065157288197
```

Copying `_manifest.json#<GENERATION>` over the live object restores `"rows": 200000`. The step then
deletes the manifest. A plain listing no longer shows it, and `--all-versions` still lists three
generations. The same copy restores it again.

**What to notice.** The overwrite did not replace the object. It added a generation and moved the
pointer. The delete did not remove the bytes. It removed the live pointer. `#<generation>` names a
specific past version. Every superseded generation is still stored and still billed, so a versioned
bucket that takes real traffic needs a lifecycle rule that expires noncurrent versions. This bucket
has none, on purpose.

### Step 6 · CSV to Parquet. Two arguments, two numbers

The step uploads `readings.parquet` into the Curated zone and lists both files:

```
  12348336  2026-09-10T18:32:27Z  gs://dsba6190-lake-65111/raw/readings/readings.csv
   2680274  2026-09-10T18:32:46Z  gs://dsba6190-lake-65111/curated/readings/readings.parquet
```

The Parquet copy is 4.6 times smaller for the same 200,000 rows. The step then copies
`tables.tf.staged` into place and applies it. `Resources: 3 added` creates one dataset and two
external tables over objects already in the bucket, so nothing is copied into BigQuery. The same
query runs against each table:

```sh
bq --project_id="$PROJECT" query --use_legacy_sql=false --nouse_cache \
  "SELECT ROUND(AVG(value), 3) AS mean_reading FROM \`$PROJECT.dsba6190_lake_$SUFFIX.readings_csv\`"
```

Both return `119.799`. `bq show -j` reads what each query cost:

| Table | Bytes Processed | Bytes Billed |
|---|---|---|
| `readings_csv` | 12,348,283 | 12,582,912 |
| `readings_parquet` | **1,600,000** | 10,485,760 |

**What to notice.** The rows and the answer are identical, and BigQuery read 7.7 times fewer bytes
from the Parquet copy. The figure 1,600,000 is exactly 200,000 rows times eight bytes, which is the
`value` column and nothing else. Columnar storage let the engine skip the other five columns. A row
format must read every byte of every row to reach one field. BigQuery bills a 10 MB minimum per
table scanned, so at this size the Parquet query billed more than it read. At production volume the
minimum disappears and the ratio becomes the whole cost. File format is a cost control.

### Step 7 · The lifecycle rule that nothing runs tonight

```sh
cp lake.tf.lifecycle lake.tf
terraform plan
```

The plan reports `Plan: 0 to add, 1 to change, 0 to destroy.` Its entire diff is two blocks: move to
`NEARLINE` at 30 days and to `ARCHIVE` at 365 days. After `terraform apply`, `gcloud storage buckets
describe --format="yaml(name,lifecycle_config)"` shows both rules on the bucket.

**What to notice.** Nothing moves tonight. Cloud Storage evaluates lifecycle rules asynchronously,
about once a day, and every object here is minutes old. The rule is the artifact. It encodes an
access-pattern decision, so a rule that moves weekly-read data to Coldline costs more than leaving
it in Standard. A rule whose action is `Delete` is also a way to destroy records that someone was
legally required to keep. Deletion rules deserve the review a production deployment gets. This
bucket has no `Delete` rule, on purpose.

### Step 8 · Retention, and a delete that fails

The step copies `vault.tf.staged` into place and applies it. The new bucket reports its policy:

```
name: dsba6190-vault-65111
retention_policy:
  effectiveTime: '2026-09-10T18:33:09.035000+00:00'
  retentionPeriod: '3600'
```

The step uploads an incident record to `raw/incident.csv` and then tries to delete it:

```
ERROR: HTTPError 403: Object 'dsba6190-vault-65111/raw/incident.csv' is subject to bucket's
retention policy or object retention and cannot be deleted or overwritten until
2026-09-10T12:33:11.232127-07:00.
```

**What to notice.** The Raw zone's immutability is now a mechanism rather than a sentence. The
object cannot be deleted or overwritten, and the refusal applies to the account that wrote it. In
the Console, the bucket's Protection tab offers Bucket Lock. Do not lock this bucket. Locking makes
the retention period permanent, including against you, and a locked bucket cannot be deleted until
every object has met its retention period. The demonstration sets one hour rather than seven years
for that reason, and step 12 is where it matters.

### Step 9 · CMEK, and crypto-shredding

The step copies `secure.tf.staged` into place, applies it, and uploads `regulated.csv`. The object
names the key version that encrypted it:

```
kms_key: projects/YOUR_PROJECT_ID/locations/us-east1/keyRings/dsba6190-demo/cryptoKeys/lake-cmek/cryptoKeyVersions/1
```

The file reads normally. Then the step disables the key version without touching the object:

```sh
gcloud kms keys versions disable 1 --key lake-cmek --keyring dsba6190-demo \
  --location us-east1 --project "$PROJECT"
```

The version reports `state: DISABLED`, and the next read fails:

```
ERROR: (gcloud.storage.cat) HTTPError 400: Cloud KMS key is disabled, destroyed, or scheduled to be destroyed.
    type: KEY_DISABLED
```

A write to the same bucket fails with the same `KEY_DISABLED` violation. `gcloud kms keys versions
enable 1` restores the version, and the read succeeds again.

**What to notice.** Nothing happened to the object. It was encrypted before this step and it is
encrypted now. The customer-managed encryption key (CMEK) did not add encryption. It changed who
holds the key. That control makes ciphertext permanently unreadable without finding every copy of
it. **Crypto-shredding** is deletion by destroying the key, and it is faster and more provable than
a delete sweep across replicas and backups. It is also the failure mode. `disable` is reversible,
`destroy` is not, and losing the key loses the data.

### Step 10 · Partition pruning, measured

The step uploads `sample/events`, the same 200,000 rows laid out as ten daily prefixes from
`dt=2026-09-08/` to `dt=2026-09-17/`. It then copies `events.tf.staged` into place and applies it.
The table's `hive_partitioning_options` sets `mode = "AUTO"` and points `source_uri_prefix` at the
directory above `dt=`. Two queries follow, one over the whole table and one with `WHERE dt =
'2026-09-17'`:

| Query | Rows | Bytes Processed |
|---|---|---|
| All partitions | 200,000 | 1,600,000 |
| `dt = '2026-09-17'` | 20,000 | **160,000** |

**What to notice.** The filtered query read exactly ten times fewer bytes, from a `WHERE` clause on
a column that exists in no file. `dt` is a directory name. BigQuery matched one prefix and never
opened the other nine objects. Partitioning also makes writes idempotent by day. Reprocessing 17
September overwrites one prefix and leaves the other nine alone. Each object here is about 200 KB,
far below the 128 MB to 1 GB target. At real volume, files that small become the small files problem
in distributed processing.

### Step 11 · The guardrail above the project

Public access prevention in step 2 is a bucket setting, and anyone with bucket permissions can
change it back. The guardrail version is an organization policy set on an organization or folder
above the project, which no project owner can override.

```sh
gcloud projects get-ancestors "$PROJECT"
gcloud organizations list
gcloud org-policies list --project="$PROJECT"
gcloud org-policies describe constraints/storage.publicAccessPrevention --project="$PROJECT" --effective
```

In the recorded run, `get-ancestors` returned one row, the project itself. Both lists returned
`Listed 0 items.` The effective policy returned `enforce: false`. The attempt to set the policy
failed with `Permission 'orgpolicy.policies.create' denied`. Your results depend on where your
project sits.

**What to notice.** A project with no organization above it has nowhere to attach an organization
policy, so the recorded run cannot show an enforced one. An organization-level public access
prevention policy overrides the bucket setting. If your project sits under an organization that
enforces it, the step 4 grant on the ungoverned bucket is refused as well, and that refusal comes
from above the project you can see.

### Step 12 · Teardown is a teaching step

`terraform destroy` plans `8 to destroy`. Seven resources go, and then the vault bucket fails:

```
Error: could not delete non-empty bucket due to error when deleting contents:
googleapi: Error 403: Object 'dsba6190-vault-65111/raw/incident.csv' is subject to
bucket's retention policy or object retention and cannot be deleted or overwritten
until 2026-09-10T12:33:11.232127-07:00, retentionPolicyNotMet
```

```sh
gcloud storage buckets update "gs://dsba6190-vault-${SUFFIX:?}" --project "${PROJECT:?}" --clear-retention-period
terraform destroy
```

The second destroy reports `Destroy complete! Resources: 1 destroyed.` The step then schedules the
key version for destruction and lists the buckets and datasets that remain.

**What to notice.** The retention policy refused Terraform exactly as it refused the `rm` in step 8.
That refusal is the difference between a control and a convention. The destroy was not atomic. Seven
resources are gone, one is not, and Terraform did not roll the seven back. The policy could be
cleared only because it was never locked. With Bucket Lock, the bucket would have stayed in the
project until every object met its retention period. The control that protects the data from you is
the same control that stops you cleaning up, so a design must plan for its own teardown.

---

## Teardown

Step 12 destroys everything Terraform built and schedules the key version for destruction. If you
stopped before step 12, run the first two lines below in that order, because the destroy fails until
the retention period is cleared. Then schedule the key version for destruction, using the version
number `live-setup.sh` printed, and confirm that nothing remains.

```sh
gcloud storage buckets update "gs://dsba6190-vault-${SUFFIX:?}" --project "${PROJECT:?}" --clear-retention-period
cd "${WORK:?}" && terraform destroy
gcloud kms keys versions destroy 1 --key lake-cmek --keyring dsba6190-demo --location us-east1 --project "${PROJECT:?}"
gcloud storage ls --project "$PROJECT"
bq --project_id="$PROJECT" ls
```

Every name is written `${NAME:?}`, so an empty variable refuses to run instead of acting on the
wrong thing. A 404 on a bucket means that step never ran and there is nothing to remove. The
listings should show none of the four `dsba6190-*-<suffix>` buckets and no `dsba6190_lake_<suffix>`
dataset.

Two things remain by design. Google does not permit deleting the key ring `dsba6190-demo` or the key
`lake-cmek`. Neither bills once no version is live, and `live-setup.sh` reuses them on the next run.
A version scheduled for destruction still bills until the 24-hour window closes. The four enabled
APIs are free to leave on.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `could not find default credentials` | Run `gcloud auth application-default login` |
| `403 does not have storage.buckets.create` | The wrong project or account is active. Run `gcloud config set project YOUR_PROJECT_ID` |
| `bucket already exists` | Another project holds the name. Re-run `live-setup.sh` with a different five-digit suffix |
| `Cloud KMS API has not been used in project` | The API was enabled seconds ago. Wait one minute and re-run `live-setup.sh` |
| `key version is scheduled for destruction` | A previous teardown scheduled the version. Re-run `live-setup.sh`, which restores it or creates a new primary version |
| `No module named 'pyarrow'` | Run `python3 -m pip install pyarrow`, or install `uv` |
| `Already Exists: Dataset` | A previous run's dataset survived. Run `bq rm -r -f -d "dsba6190_lake_${SUFFIX:?}"` |
| The `dt=` prefixes are missing | The generator wrote into a stale directory. Re-run `live-setup.sh`, which recreates the working directory |
| The anonymous `curl` in step 4 returns `AccessDenied` | The binding has not propagated. Wait fifteen seconds and run `curl` again |
| The step 4 binding on the ungoverned bucket fails with `412` | An organization policy above your project enforces public access prevention. Step 11 explains it |
| The read in step 9 still succeeds after the disable | A cached key is serving the read. Run it again after twenty seconds. The write refuses immediately |
| `Bytes Processed` reads `0` | The result came from cache. Keep `--nouse_cache` on the query |
| The external table returns `Not found: URI` | The upload in step 6 or step 10 did not finish. Re-run the copy, then `terraform apply` |
| The first destroy in step 12 succeeds | More than an hour passed since step 8, so the retention period expired. `capture/58-destroy-refused.txt` holds the refusal |

---

## Files

| Path | What it is |
|---|---|
| `01-plain/main.tf` | Providers, variables and the ungoverned baseline bucket |
| `02-governed/` to `07-partitioned/` | The file each step stages into the working directory |
| `sample/make-sample.py` | Generates the seeded telemetry: one CSV, one Parquet file and ten daily partitions |
| `steps/` | One Bash script per step, and `menu.sh` |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and the real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
