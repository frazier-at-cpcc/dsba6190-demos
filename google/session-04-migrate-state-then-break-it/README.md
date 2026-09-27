# Session 4 live demo · migrate state, then break it

The hour-long Terraform state demonstration from
[`../../lecture-04-terraform-state-automation.md`](../../lecture-04-terraform-state-automation.md),
built as runnable source and captured as real output.

**Captured 10 September 2026** against project `YOUR_PROJECT_ID` (UNC Charlotte Demo),
Terraform v1.5.7, `hashicorp/google` v5.45.2, `hashicorp/random` v3.9.0, `hashicorp/time` v0.14.1.
Every line in `capture/` is real command output. Nothing is illustrated or reconstructed.

The run applies a small estate with local state, migrates it to a versioned Cloud Storage backend,
collides two applies on the lock, kills one and recovers the stale lock, deletes the state object
and restores a prior generation, adopts two hand-made buckets by import, drifts a label and a
resource, performs `state rm` and `state mv`, and finishes on the `prevent_destroy` and
`force_destroy` pair. It destroys everything on exit. Total cost is under five cents; four buckets
and one topic live for about twenty minutes and hold a few kilobytes, and the dominant line is the
versioned state bucket. The figure matches the Session 4 row in
[`../../../docs/DEMO-DEVELOPMENT-PLAN.md`](../../../docs/DEMO-DEVELOPMENT-PLAN.md) section 7.

## Why this demonstration is an hour

The guided lab that follows it, **Manage Terraform State (GSP752)**, leaves four gaps that the
session has to close itself. They are recorded in
[`../teaching-notes.md`](../teaching-notes.md) and each one has a step here.

| Gap in Lab 4 | Step that closes it |
|---|---|
| State locking is explained in prose and never demonstrated | 5 and 6 |
| Secrets in state are never raised at all | 1 and 3 |
| Import is taught against a Docker container, not Google Cloud | 8 |
| `force_destroy = true` appears in the cleanup with no counterweight | 11 |

## Layout

| Path | What it is |
|---|---|
| `01-local-state/` | The baseline. A bucket, a topic, and a generated password, on local state |
| `02-remote-backend/` | The `backend "gcs"` block, templated because a backend block cannot hold a variable |
| `03-lock/` | The baseline plus a `time_sleep` slow enough to hold the lock for ninety seconds |
| `04-import/` | Two hand-made buckets adopted two ways: the CLI form and the plannable `import` block |
| `05-state-mv/` | The same estate with one resource address renamed |
| `06-destroy-controls/` | `prevent_destroy` in `main.tf`, `force_destroy` in `main-forced.tf` |
| `capture/` | Full real output, one file per command |
| `capture.sh` | The headless recorder. Re-runnable, self-cleaning |
| `live-setup.sh` | Stages the working directory **and applies the baseline** |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |

## Two things this demo does that Session 3 does not

**`live-setup.sh` applies.** Session 3 stages and stops, because its first step is a plan against
nothing. This demonstration begins from an estate that already exists on local state, so the setup
script has to build that estate. It applies with the local backend on purpose, because step 1 reads
the local file and step 3 migrates it.

**Two files are templates rather than configuration.** A `backend` block may not contain a
variable, and in Terraform 1.5 neither may the `id` of an `import` block. `live-setup.sh` and
`capture.sh` substitute the real bucket names. The restriction is the lecture's own watch-for, so
the templates are the honest representation rather than a workaround.

## Re-capture

```sh
./capture.sh YOUR_PROJECT_ID
```

The name suffix is derived per run, so a re-capture does not collide with a previous one in the
global bucket namespace. Re-run before class if the provider has moved a major version, because
plan output gains and loses attributes between releases and the runbook quotes it literally.

The run takes about twenty minutes. Two steps wait on a ninety-second `time_sleep`, and step 6
kills a running apply with `SIGKILL` on purpose to produce a genuinely stale lock.

## What each capture is for

| File | Step | The teaching moment |
|---|---|---|
| `01-state-list.txt` | 1 | Three addresses. This is what Terraform believes it manages |
| `02-output-redacted.txt` | 1 | `db_admin_password = <sensitive>` |
| `03-state-show-redacted.txt` | 1 | `result = (sensitive value)`. Even `state show` hides it |
| `04-state-file-on-disk.txt` | 1 | The file is right there, next to the configuration |
| `05-password-in-plain-text.txt` | 1 | **The same value, in plain text, from the file** |
| `06-create-state-bucket.txt` | 2 | Bootstrapped by hand, because `init` needs it to exist |
| `07-enable-versioning.txt` | 2 | Versioning is the undo, and step 7 uses it |
| `08-state-bucket-controls.txt` | 2 | Uniform access, public access prevention, versioning, in one output |
| `09-backend-block.txt` | 3 | The block, and why it cannot hold a variable |
| `10-init-migrate.txt` | 3 | `Successfully configured the backend "gcs"!` |
| `11-state-object-in-bucket.txt` | 3 | `envs/dev/default.tfstate`. The prefix is the environment boundary |
| `12-password-in-the-bucket.txt` | 3 | **The same string again, now in the bucket.** This is why the bucket is a secret store |
| `13-plan-no-changes.txt` | 4 | `No changes.` The record moved; reality did not |
| `14-local-copy-left-behind.txt` | 4 | The stale local backup still holds the password. Migration cleans up nothing |
| `15-apply-holding-the-lock.txt` | 5 | The first terminal, holding the lock for ninety seconds |
| `16-lock-refused.txt` | 5 | **`Error acquiring the state lock`** with the full `Lock Info` block |
| `17-apply-then-killed.txt` | 6 | An apply killed with `SIGKILL`, which is what a crashed run looks like |
| `18-stale-lock.txt` | 6 | The lock outlived the process that took it |
| `19-force-unlock.txt` | 6 | The recovery, and the only case in which it is correct |
| `20-plan-after-unlock.txt` | 6 | Working again |
| `21-state-object-deleted.txt` | 7 | The state object, gone |
| `22-plan-with-no-state.txt` | 7 | **Terraform proposes to build the estate a second time.** State loss, live |
| `23-generations.txt` | 7 | The generations versioning kept |
| `24-restore-generation.txt` | 7 | The undo |
| `25-plan-restored.txt` | 7 | `No changes` again |
| `26-legacy-guess.txt` | 8 | The configuration written from memory, which is wrong |
| `27-import-cli.txt` | 8 | `terraform import` against Google Cloud rather than Docker |
| `28-plan-after-import.txt` | 8 | **The plan would destroy the bucket it adopted thirty seconds earlier.** Import populates state, not configuration |
| `29-plan-config-matches.txt` | 8 | Written from the plan instead of from memory |
| `30-import-block.txt` | 8 | The declarative form |
| `31-plan-import-block.txt` | 8 | `1 to import` in a plan, which means it can be reviewed |
| `32-apply-import-block.txt` | 8 | The adoption |
| `33-drift-label.txt` | 9 | Someone changed a label and told nobody |
| `34-plan-drift-label.txt` | 9 | Terraform proposes to revert it |
| `35-refresh-only.txt` | 9 | `-refresh-only` accepts reality into the record |
| `36-plan-still-drifted.txt` | 9 | **And still proposes to revert it.** Refresh changes the record, not the intent |
| `37-drift-delete.txt` | 9 | A resource deleted out of band |
| `38-plan-drift-delete.txt` | 9 | Terraform proposes to recreate it |
| `39-apply-reconcile.txt` | 9 | The configuration wins |
| `40-state-list-full.txt` | 10 | The estate after the imports |
| `41-state-rm.txt` | 10 | Forgetting without destroying |
| `42-plan-after-rm.txt` | 10 | Terraform would now build a duplicate |
| `43-plan-forgotten.txt` | 10 | Clean, and the bucket is now yours to manage by hand |
| `44-plan-address-change.txt` | 10 | An address change reads as a delete and a create |
| `45-state-mv.txt` | 10 | The refactor Session 3 needed and did not have |
| `46-plan-after-mv.txt` | 10 | `No changes`. The resource never moved |
| `47-data-arrives.txt` | 11 | An object nobody has a copy of |
| `48-prevent-destroy.txt` | 11 | **Terraform refuses the delete** |
| `49-bucket-not-empty.txt` | 11 | The second control, and a different refusal |
| `50-force-destroy-apply.txt` | 11 | The inverse, made explicit |
| `51-destroy-succeeds.txt` | 11 | Gone, and so is the data |

## The password in the captures is masked

`random_password.db_admin` generates twenty-four characters that never protected anything and were
destroyed with the rest of the estate. The captures still replace them with asterisks of the same
length, because a course that teaches "never commit state to source control" should not commit a
plain-text secret to source control to prove it. The value is live on screen in the room, which is
where the point lands anyway.

## Performing it live

[`Session-04-Live-Demo-Runbook.pdf`](Session-04-Live-Demo-Runbook.pdf) is the document to hold while
teaching. It is built from [`RUNBOOK.md`](RUNBOOK.md) by `python3 build-runbook-pdf.py`, so edit the
markdown and rebuild rather than the PDF. It carries pre-class setup, the eleven steps with exact
commands, real expected output and what to notice, timing against the deck's slide numbers, the
teardown, and what to do when something fails in front of the room.

Stage the working directory with [`live-setup.sh`](live-setup.sh) about thirty minutes before class.

**Do not run `capture.sh` in class.** It is the headless recorder. It uses `-auto-approve`, it kills
a running apply on purpose, it prints nothing worth watching, and it destroys everything through an
exit trap.

## Teardown leaves two things behind on purpose

`terraform destroy` cleans up what Terraform manages. It does not clean up the state bucket, which
was created by hand, and it does not clean up the bucket that step 10 told Terraform to forget. A
run that stops before step 8 also leaves the annex bucket, because nothing has adopted it yet. All
three `gcloud` commands are in the runbook's teardown section and in the output of `live-setup.sh`.
That asymmetry is a teaching point rather than an oversight, and it is worth saying out loud at 2:00.

`capture.sh` has no such asymmetry. Its exit trap removes every bucket by name whatever happened,
which is why the recorder is safe to abort and the live run is not.
