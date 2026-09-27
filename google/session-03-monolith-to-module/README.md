# Session 3 demonstration · Monolith to module

This demonstration accompanies Session 3, Infrastructure as Code. Queen City Trip Analytics, the
fictional South End analytics firm used across the course, codifies the nightly-trips bucket it
created by hand in Session 1. The firm turns that bucket into one module for development, test and
production. It then hardens the module with validated inputs, enforced labels, deletion controls,
environments from one map, a virtual machine module, and drift reported as an exit code.

Every command was run end to end on 27 September 2026 with Terraform v1.5.7 and `hashicorp/google`
v5.45.2, and `capture/` holds the real output of each one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 3 | The bucket was created in 1 s. The second apply reported no changes | `03`, `04` |
| 5 | The name line carries `# forces replacement`, and the plan reads 1 to add, 1 to destroy | `07` |
| 8 | `environment = "production"` fails at plan time. The module overrules the caller's `sandbox` with `dev` | `14`, `17` |
| 9 | `prevent_destroy` refuses both buckets. With the guard deleted, a bucket holding one file still refuses | `20`, `21`, `22` |
| 10 | Two `moved` blocks plan 0 to add and 0 to destroy. Adding `test` plans exactly 1 to add | `23`, `25` |
| 11 | Validation refuses `n2-standard-32`. The `e2-micro` refuses a `gcloud` delete. It lived 159 s and cost $0.000370, and the refused type lists at $1,134.34 a month | `27` to `33` |
| 12 | `plan -detailed-exitcode` returns 0, then 2 after a label edit. The lock file pins 5.45.2 | `34` to `39` |
| 13 | The project holds 0 buckets and 0 instances, and the state holds 0 resources | `42`, `43` |

## Known issues and fixes

- `live-setup.sh` refuses to overwrite a working directory whose state still tracks resources. Run
  the teardown it prints, then stage again.
- Steps 7, 10 and 11 introduce modules. Run `terraform init` after each stage copy, or `plan` fails
  with `Error: Module not installed`.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `01-monolith/` to `08-vm/` | Eight Terraform stages, one directory each |
| `live-setup.sh` | Stages the working directory and initializes Terraform. It creates nothing and never destroys |
| `capture.sh`, `capture/` | The recorder and its 44 output files. An exit trap deletes everything it created |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
