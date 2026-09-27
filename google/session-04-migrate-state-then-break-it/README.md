# Session 4 demonstration · Migrate state, then break it

This demonstration accompanies Session 4, Terraform State and Automation. Queen City Trip Analytics,
the fictional South End analytics firm used across the course, gains a second engineer and moves its
Terraform state off one engineer's laptop. The demonstration applies a small estate on local state,
migrates it to a versioned Cloud Storage backend, collides two applies on the lock, kills one and
clears the stale lock, deletes the state object and restores a prior generation, adopts two
hand-made buckets by import, drifts a label and a resource, runs `state rm` and `state mv`, and ends
on the `prevent_destroy` and `force_destroy` pair.

Every command was run end to end on 10 September 2026 with Terraform v1.5.7, `hashicorp/google`
v5.45.2, `hashicorp/random` v3.9.0 and `hashicorp/time` v0.14.1, and `capture/` holds the real
output of each one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | `terraform output` and `state show` hide the password, and the local state file holds it in plain text | `02`, `03`, `05` |
| 3 | `init -migrate-state` moves the state to `envs/dev/default.tfstate`, and the password moves with it | `10`, `11`, `12` |
| 4 | The plan shows `No changes`, and a 4,599-byte `terraform.tfstate.backup` still holds the password | `13`, `14` |
| 5 | A second plan fails with `Error acquiring the state lock`, an HTTP 412 on a `.tflock` object | `16` |
| 6 | An apply killed with `SIGKILL` leaves its lock behind, and `force-unlock` clears it | `18`, `19` |
| 7 | With the state object deleted, the plan proposes `4 to add`. Restoring the 5,111-byte generation returns `No changes` | `22`, `23`, `25` |
| 8 | After `terraform import`, the plan proposes to destroy the bucket it adopted. The `import` block plans `1 to import` | `28`, `31` |
| 9 | After `apply -refresh-only`, the plan still proposes to revert the label | `35`, `36` |
| 10 | `state mv` turns a destroy-and-create plan into no resource changes | `44`, `45`, `46` |
| 11 | `prevent_destroy` refuses four destroys at plan time, and the provider refuses to delete a bucket that holds objects | `48`, `49` |

## The password in the captures is masked

`random_password.db_admin` generates twenty-four characters that protected nothing and were
destroyed with the rest of the estate. The captures still replace them with asterisks of the same
length. A course that teaches you never to commit state to source control does not commit a
plain-text secret to prove the point. When you run the demonstration, the value appears in full.

## Known issues and fixes

- Stopping the second apply with a single Ctrl-C releases the lock gracefully. Step 6 needs a hard
  kill, `kill -9`, to leave a stale lock.
- Answering `no` at the migration prompt, or running `-reconfigure`, starts the new backend empty.
  The next plan then proposes to build the whole estate a second time.
- A Pub/Sub topic name stays reserved for up to a minute after its deletion. Wait before the
  recreating apply in step 9.
- `terraform destroy` leaves the hand-made state bucket and the forgotten legacy bucket behind. The
  teardown in `RUNBOOK.md` removes both.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `01-local-state/` | The baseline: a bucket, a topic and a generated password, on local state |
| `02-remote-backend/` | The `backend "gcs"` block, a template because a backend block cannot hold a variable |
| `03-lock/` | The baseline plus a `time_sleep` that holds the lock for ninety seconds |
| `04-import/` | Two hand-made buckets adopted two ways, with the command-line import and with an `import` block |
| `05-state-mv/` | The same estate with one resource address renamed |
| `06-destroy-controls/` | `prevent_destroy` in `main.tf` and `force_destroy` in `main-forced.tf` |
| `live-setup.sh` | Stages the working directory and applies the baseline. It never deletes anything |
| `capture.sh`, `capture/` | The recorder and its 51 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
