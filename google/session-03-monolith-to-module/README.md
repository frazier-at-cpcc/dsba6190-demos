# Session 3 live demo · monolith to module, hardened for A3

The hour-long infrastructure-as-code demonstration for Session 3, Infrastructure as Code. Queen City
Trip Analytics, the fictional South End firm used across the course, codifies the nightly-trips
bucket it created by hand in Session 1, turns it into a module for development, test, and
production, and then hardens that module against each requirement in A3.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`, Terraform
v1.5.7, `hashicorp/google` v5.45.2. It replaces the fifteen-minute, seven-step demonstration the
session taught on 3 September. Steps 1 to 7 keep that demonstration's Terraform unchanged.

## What the rehearsal changed

- **The first seven steps now run in teaching order.** The September deck ran the drift step before
  the module step and numbered them 7 and 6. The drift step is now step 6 and the module step 7.
- **Six steps were added for A3.** Each A3 requirement is performed against the real project:
  validation, enforced labels, deletion controls, environments from one map, a VM module, and drift
  as an exit code.
- **`live-setup.sh` refuses to wipe live state.** The earlier version deleted its working directory
  unconditionally, which would have orphaned any resource still in state.
- **Masking covers every email address**, not only the active account, and the project number,
  which the September capture printed in the replacement plan.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 3 | Bucket created in 1 s; the second apply reports no changes | `03`, `04` |
| 5 | `# forces replacement` on the name line; 1 to add, 1 to destroy | `07` |
| 8 | `environment = "production"` refused at plan; caller's `sandbox` overruled to `dev` | `14`, `17` |
| 9 | `prevent_destroy` refuses both buckets; with the guard deleted, a bucket holding one file still refuses | `20`, `21`, `22` |
| 10 | Two `moved` blocks: 0 to add, 0 to destroy. Adding `test`: exactly 1 to add | `23`, `25` |
| 11 | `n2-standard-32` refused; `e2-micro` protected against `gcloud`; 159 s, $0.000370; the refused type lists at $1,134.34 a month | `27` to `33` |
| 12 | `plan -detailed-exitcode` returns 0, then 2 after a label edit; lock file at 5.45.2 | `34` to `39` |
| 13 | 0 buckets, 0 instances, 0 resources in state | `42`, `43` |

## Layout

| Path | What it is |
|---|---|
| `01-monolith/` to `08-vm/` | Eight Terraform stages, one directory each |
| `live-setup.sh` | Stages the working directory and initializes Terraform. Creates nothing; never destroys |
| `capture.sh`, `capture/` | The recorder and its 44 files of real output. Self-cleaning through an exit trap |
| `RUNBOOK.md`, `Session-03-Live-Demo-Runbook.pdf` | The instructor document. Rebuild the PDF with `uv run --quiet --with markdown python3 build-runbook-pdf.py` |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
