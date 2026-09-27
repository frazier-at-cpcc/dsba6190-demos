# Session 4 demonstration · An infrastructure pipeline with four gates

This demonstration accompanies Session 4, Terraform State and Automation. It delivers two Cloud
Storage buckets through a six-stage pipeline on GitHub Actions. A pull request posts its own plan. A
policy gate rejects a bad plan without a human. An approval gate waits for a person. The apply runs
as a service account through Workload Identity Federation, and a scheduled plan finds drift.

Every command was run end to end on 10 September 2026, and `capture/` holds the real output of each
one. The recorded run used Terraform v1.5.7, `hashicorp/google` v5.45.2 and Conftest v0.69.0. Read
`RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| Staging | The first apply waited at the `production` gate, then created both buckets | `03`, `04`, `05` |
| 2 | A three-line label change planned 0 to add, 2 to change, 0 to destroy, and passed all 4 policy tests | `07`, `08`, `09` |
| 3 | The apply job waited for a reviewer, then applied the saved plan: 0 added, 2 changed, 0 destroyed | `11`, `12`, `13` |
| 4 | Policy rejected a grant to `allUsers` and named the resource | `14`, `15`, `16` |
| 5 | A one-line location change planned 1 to add and 1 to destroy, and policy rejected the replace | `17`, `18` |
| 6 | A label changed in the Console opened drift issue #4, and restoring the label closed it | `19` to `24` |
| 7 | `terraform destroy` removed both buckets after `prevent_destroy` was lifted locally | `99` |

Each pull-request check ran for 12 to 18 seconds on a hosted runner. The recorded run cost under
$0.01.

## Credentials

No credential is stored anywhere. GitHub Actions presents an OpenID Connect token. A Workload
Identity Federation provider in your project accepts it only when the token names your repository,
and exchanges it for a short-lived token for the service account `github-actions-tf`. The service
account holds Storage Admin on the project, because creating a bucket needs a project-scoped
permission that no narrower predefined role carries.

The repository is public. Required reviewers on a GitHub environment are free on a public repository
and need a paid plan on a private one. The repository holds a project ID, which is not a secret, and
no credential of any kind.

## Known issues and fixes

- A bucket that exists but is missing from state makes `apply` fail with `409`. `live-setup.sh` now
  imports such a bucket before it applies.
- An apply run that waits at the gate holds the `terraform-state` concurrency group, so every
  pull-request check queues behind it. `live-setup.sh` pushes its reset commit with `[skip ci]`, so
  it creates no such run.
- The daily drift plan reports destroyed buckets as drift. The teardown disables the drift workflow,
  and `live-setup.sh` enables it again.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `repo/` | The pipeline repository: Terraform for two buckets, `policy/buckets.rego` and three workflows |
| `bootstrap.sh` | One-time Google Cloud and GitHub setup. It is idempotent |
| `live-setup.sh` | Stages the repository, the two buckets and three pull-request branches. It never destroys |
| `capture.sh`, `capture/` | The recorder and its 23 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |

`repo/` holds `main.tf`, `variables.tf`, `versions.tf`, `outputs.tf` and `terraform.tfvars`, with a
partial `gcs` backend whose bucket and prefix arrive from the pipeline. `policy/buckets.rego` holds
four Conftest rules. `pull-request.yml` runs stages 1 to 3, `apply.yml` runs stages 4 and 5, and
`drift.yml` runs stage 6.
