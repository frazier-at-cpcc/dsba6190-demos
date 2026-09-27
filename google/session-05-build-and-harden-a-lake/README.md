# Session 5 live demo · build and harden a lake

The hour-long Cloud Storage governance demonstration from
[`../../lecture-05-storage-data-lakes.md`](../../lecture-05-storage-data-lakes.md), built as runnable
source and captured as real output.

**Captured 10 September 2026** against project `YOUR_PROJECT_ID` (UNC Charlotte Demo),
Terraform v1.5.7, `hashicorp/google` v5.45.2, Google Cloud SDK 584.0.0. Every line in `capture/` is
real command output. Nothing is illustrated or reconstructed.

The run builds a governed bucket beside an ungoverned one, creates the four zones and a quarantine
prefix, makes the ungoverned bucket public and fetches the object anonymously, watches public access
prevention and uniform bucket-level access refuse the same thing two different ways, overwrites and
deletes an object and restores both from prior generations, measures CSV against Parquet through two
BigQuery external tables, adds lifecycle rules, sets a retention policy and fails a delete, encrypts
a bucket with a customer-managed key and makes its contents unreadable by disabling that key,
measures partition pruning at ten to one, records what an organization policy would add and why this
project cannot show it, and finishes on a `terraform destroy` that the retention policy refuses.

Total cost is under ten cents. Four buckets and one dataset live for about fifteen minutes and hold
about 17 MB, the four measured queries read 27 MB against a 1 TiB monthly free allowance, and the
only charge that outlives the evening is a Cloud KMS key version at $0.06 per month. The figure
matches the Session 5 row in
[`../../../docs/DEMO-DEVELOPMENT-PLAN.md`](../../../docs/DEMO-DEVELOPMENT-PLAN.md) section 7.

## Why this demonstration is an hour

`../teaching-notes.md` carries no Session 5 entry, because Lab 5 is a Google Skills course template
rather than a single lab and no capture of it exists in `labs/captures/`. The gaps below are read
from the Lab 5 brief in [`../../../labs/briefs.md`](../../../labs/briefs.md) and from the A5 brief in
[`../../../assignments/briefs.md`](../../../assignments/briefs.md), and each one has a step here.

| Gap between Lab 5 and what A5 grades | Step that closes it |
|---|---|
| The lab sets bucket controls. It never shows one refusing anything | 4 |
| The lab compares CSV and Parquet object sizes. It never measures bytes scanned | 6 |
| The lab warns that retention policies prevent cleanup. It never shows the refusal | 8 and 12 |
| CMEK and crypto-shredding appear in the lecture and in neither the lab nor the assignment's mechanics | 9 |
| Hive partitioning is a naming convention in the lab and a measured cost control in A5 | 10 |
| Organization Policy is named in the lab's pitfalls with no way to see it | 11 |

## Layout

| Path | What it is |
|---|---|
| `01-plain/` | The baseline. A bucket with no controls, applied before class so step 4 has a comparison |
| `02-governed/` | The governed bucket from slide 22: uniform access, public access prevention, versioning, labels |
| `03-tables/` | The BigQuery dataset and the CSV and Parquet external tables step 6 measures |
| `04-lifecycle/` | The same governed bucket, plus the two `lifecycle_rule` blocks |
| `05-retention/` | The bucket with a one-hour `retention_policy`, which steps 8 and 12 argue with |
| `06-cmek/` | The bucket encrypted with the customer-managed key |
| `07-partitioned/` | The external table with `hive_partitioning_options`, which step 10 measures |
| `sample/` | The seeded generator for 200,000 rows of invented telemetry, in three layouts |
| `capture/` | Full real output, one file per command |
| `capture.sh` | The headless recorder. Re-runnable, self-cleaning |
| `live-setup.sh` | Stages the working directory, **applies the ungoverned baseline**, and creates the key |

## Three things this demo does that Session 4 does not

**Each stage adds a file rather than replacing one.** Terraform reads every `.tf` file in a
directory, so `cp lake.tf.staged lake.tf` is the entire edit and the plan that follows shows exactly
one change. Session 4 swapped whole `main.tf` variants because its steps changed resources that
already existed. Session 5 mostly adds resources, and a one-file diff reads better from the back row.
The one step that changes an existing resource, step 7, is the one whole-file swap.

**Two resources are deliberately outside Terraform.** The Cloud KMS key ring and key are created by
`live-setup.sh`, because a key ring cannot be deleted and Terraform should not manage a resource it
cannot remove. The zone prefixes are created with `gcloud` in step 3, because a prefix is an object
rather than a resource, and declaring one in HCL would teach the wrong model of object storage.

**The sample data is generated, not committed.** `sample/make-sample.py` is seeded, so a re-capture
produces byte-identical files and the measurements in `RUNBOOK.md` stay true. Twelve megabytes of
invented telemetry do not belong in a Git repository, and `.gitignore` keeps the generated output
out of it.

## Re-capture

```sh
./capture.sh YOUR_PROJECT_ID
```

The name suffix is derived per run, so a re-capture does not collide with a previous one in the
global bucket namespace. Re-run before class if the provider has moved a major version, because plan
output gains and loses attributes between releases and the runbook quotes it literally.

The run takes about five minutes. Two steps poll rather than sleep, because a Cloud KMS key state
change and a public IAM binding both propagate on their own schedule.

**The recorder leaves two things behind on purpose.** The exit trap schedules the key version for
destruction, and the key ring and key survive because Google does not permit deleting them. Enabling
an API is not reversed. Both are in the runbook's teardown checklist with the reason attached, along
with the note that `lake-cmek` carries Google's 30-day scheduled-destruction default because it was
created before the script asked for the 24-hour minimum, and that the window cannot be changed after
a key exists.

## What each capture is for

| File | Step | The teaching moment |
|---|---|---|
| `01-governed-hcl.txt` | 1 | Four governance controls, readable before anything exists |
| `02-plan-governed.txt` | 1 | The plan is the review artifact |
| `03-apply-governed.txt` | 2 | One bucket added, two outputs |
| `04-lake-controls.txt` | 2 | Uniform access, public access prevention, versioning, labels, in one output |
| `05-staging-controls.txt` | 2 | **The same command, and every control is off or absent** |
| `06-create-zones.txt` | 3 | Five prefixes and zero directories |
| `07-upload-raw-csv.txt` | 3 | 200,000 rows land in Raw exactly as they arrived |
| `08-list-zones.txt` | 3 | The key is one string with slashes in it |
| `09-public-on-staging.txt` | 4 | `allUsers` accepted, on the bucket nobody governed |
| `10-public-object-fetched.txt` | 4 | **The object, served to an anonymous request** |
| `11-public-refused-lake.txt` | 4 | `HTTPError 412`. Public access prevention is a refusal |
| `12-acl-refused-lake.txt` | 4 | `HTTPError 400`. A second control, refusing a different route |
| `13-revoke-public.txt` | 4 | The exposure undone before the step ends |
| `14-manifest-v1.txt` | 5 | The manifest the nightly run wrote |
| `15-manifest-overwritten.txt` | 5 | The rerun nobody reviewed, and `"rows": 0` |
| `16-all-versions.txt` | 5 | Two generations. The overwrite added, it did not replace |
| `17-restore-generation.txt` | 5 | The undo, by generation number |
| `18-manifest-restored.txt` | 5 | Back to 200,000 |
| `19-delete-live-version.txt` | 5 | A delete rather than an overwrite |
| `20-object-gone.txt` | 5 | The listing without it |
| `21-versions-survive-delete.txt` | 5 | **Three generations still there.** Delete moved a pointer |
| `22-restore-after-delete.txt` | 5 | The same undo works for a delete |
| `23-upload-parquet.txt` | 6 | The curated copy |
| `24-object-sizes.txt` | 6 | 11.78 MiB against 2.56 MiB, the same rows |
| `25-apply-tables.txt` | 6 | Two external tables. Nothing copied into BigQuery |
| `26-query-csv.txt` | 6 | `mean_reading = 119.799` |
| `27-bytes-csv.txt` | 6 | 12,348,283 bytes processed. The whole file |
| `28-query-parquet.txt` | 6 | **The same answer** |
| `29-bytes-parquet.txt` | 6 | **1,600,000 bytes.** 200,000 rows times one eight-byte column |
| `30-plan-lifecycle.txt` | 7 | An in-place update whose whole diff is two blocks |
| `31-apply-lifecycle.txt` | 7 | `0 to add, 1 to change` |
| `32-lifecycle-in-place.txt` | 7 | The rules on the bucket, and nothing moving tonight |
| `33-apply-retention.txt` | 8 | The bucket with a retention policy |
| `34-retention-policy.txt` | 8 | `retentionPeriod: '3600'`, and an effective time |
| `35-upload-to-vault.txt` | 8 | The record that has to survive |
| `36-delete-refused.txt` | 8 | **`HTTPError 403`. Cannot be deleted or overwritten, including by you** |
| `37-apply-cmek.txt` | 9 | The bucket with a customer-managed key |
| `38-upload-cmek.txt` | 9 | Regulated data lands |
| `39-object-key-name.txt` | 9 | The key version that encrypted it, named on the object |
| `40-read-key-enabled.txt` | 9 | Readable |
| `41-disable-key-version.txt` | 9 | `state: DISABLED`. Nothing happened to the object |
| `42-read-key-disabled.txt` | 9 | **`KEY_DISABLED`. Crypto-shredding, in one error message** |
| `43-write-key-disabled.txt` | 9 | New data cannot land either |
| `44-enable-key-version.txt` | 9 | `state: ENABLED`, because `disable` is the reversible one |
| `45-read-key-restored.txt` | 9 | Readable again |
| `46-upload-events.txt` | 10 | The partitioned copy |
| `47-list-partitions.txt` | 10 | Ten `dt=` prefixes, ending on the session's own date |
| `48-apply-events-table.txt` | 10 | `hive_partitioning_options`, applied |
| `49-query-all-partitions.txt` | 10 | 200,000 rows |
| `50-bytes-all-partitions.txt` | 10 | 1,600,000 bytes |
| `51-query-one-partition.txt` | 10 | 20,000 rows |
| `52-bytes-one-partition.txt` | 10 | **160,000 bytes. Ten times fewer, from a column that is a directory name** |
| `53-project-ancestors.txt` | 11 | One row, and it is the project. There is no organization |
| `54-organizations-list.txt` | 11 | `Listed 0 items.` |
| `55-org-policies-list.txt` | 11 | `Listed 0 items.` |
| `56-org-policy-effective.txt` | 11 | `enforce: false`, which is what inherited means with nothing above |
| `57-org-policy-set-refused.txt` | 11 | **`orgpolicy.policies.create` denied.** The guardrail cannot be demonstrated here |
| `58-destroy-refused.txt` | 12 | Seven resources destroyed, one refused, and no rollback |
| `59-clear-retention.txt` | 12 | The policy removed, because it was never locked |
| `60-destroy-succeeds.txt` | 12 | Gone |

## Step 11 is a capture step, and the instructor's environment is why

`docs/DEMO-DEVELOPMENT-PLAN.md` section 9, decision 2, records `Decided 10 Sep: yes` against the
question of whether `YOUR_PROJECT_ID` sits inside a Google Cloud organization with
`orgpolicy.policyAdmin` held on it. **Verification on 10 September contradicts that.**
`gcloud projects get-ancestors` returns one row, the project itself.
`gcloud organizations list` returns `Listed 0 items.` `gcloud org-policies set-policy --project`
returns `Permission 'orgpolicy.policies.create' denied`. All three are captured in files 53 to 57.

Step 11 therefore stays what the plan's own step table always called it: a capture step, presented
with the real evidence that this project sits outside any organization, rather than a screenshot of
an enforced policy that the course cannot produce. That is the repository standard applied to itself.
The decision row in section 9 should be corrected before the Session 2 build reaches its own step 11,
which the same plan says depends on the same answer.

## The account and the project number are masked

`capture.sh` runs a masking pass over every file before it finishes. It replaces the authenticated
account with `instructor@example.edu`, the project number with `PROJECT_NUMBER`, the opaque
troubleshooter token in an IAM denial with `ERROR_ID`, and the home directory with `~`. The project
id stays, because it is on every slide and the runbook quotes it. Nothing in the demonstration
generates a secret, and the one file that reads like sensitive data, `regulated.csv`, contains two
invented rows about a cracked part.

## Performing it live

[`Session-05-Live-Demo-Runbook.pdf`](Session-05-Live-Demo-Runbook.pdf) is the document to hold while
teaching. It is built from [`RUNBOOK.md`](RUNBOOK.md) by `python3 build-runbook-pdf.py`, so edit the
markdown and rebuild rather than the PDF. It carries pre-class setup, the twelve steps with exact
commands, real expected output and what to notice, timing against the deck's slide numbers, the
teardown checklist, and what to do when something fails in front of the room.

Stage the working directory with [`live-setup.sh`](live-setup.sh) about thirty minutes before class.
The margin is not for the resources, none of which takes longer than a second to create. It is for
the Cloud KMS API, which takes a minute to propagate after it is first enabled, and for the IAM
binding on the key, which step 9 has no room to wait for.

**Do not run `capture.sh` in class.** It is the headless recorder. It uses `-auto-approve`, it makes
a bucket briefly public on purpose, it disables an encryption key on purpose, and it destroys
everything through an exit trap.

## Teardown fails on purpose, and that is step 12

`terraform destroy` refuses while the retention policy holds an object younger than one hour. The
runbook's step 12 performs the refusal, clears the policy, and destroys again, so the ordinary case
needs nothing after class. If the demonstration stopped before step 12, run the two lines
`live-setup.sh` printed, in that order, and then schedule the key version for destruction, which is
never part of the demonstration.

`capture.sh` has the same asymmetry handled for it. Its exit trap clears the retention period on
every bucket before removing it, which is why the recorder is safe to abort and the live run is not.
