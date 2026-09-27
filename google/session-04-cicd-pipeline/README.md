# Session 4 · the infrastructure pipeline, worked

A companion to the hour-long Session 4 demonstration. Where that demonstration performs state,
locking, import, and drift at one terminal, this one performs the six-stage delivery pipeline that
Concept Block 2 describes and that Assignment A4 asks students to specify: a pull request that posts
its own plan, a policy gate that rejects without a human, an approval gate that a human must open,
an apply that runs as a service account, and a scheduled plan that finds drift.

It runs on the instructor's GitHub account and the UNC Charlotte demo project.

| Item | Where |
|---|---|
| Repository on GitHub | https://github.com/frazier-at-cpcc/dsba6190-infrastructure-pipeline |
| Source of truth for that repository | [`repo/`](repo/) |
| One-time setup, Google Cloud and GitHub | [`bootstrap.sh`](bootstrap.sh) |
| Stage the room before class | [`live-setup.sh`](live-setup.sh) |
| Bash notebooks, commands only | [`prep.ipynb`](prep.ipynb), [`demo.ipynb`](demo.ipynb), [`build-notebook.py`](build-notebook.py) |
| Headless rehearsal and recorder | [`capture.sh`](capture.sh) |
| Instructor runbook | [`RUNBOOK.md`](RUNBOOK.md), built as [`Session-04-CICD-Pipeline-Runbook.pdf`](Session-04-CICD-Pipeline-Runbook.pdf) |
| Real output from the rehearsal | [`capture/`](capture/) |

## What `repo/` holds

- `main.tf`, `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars`: two Cloud Storage
  buckets, one with `prevent_destroy`, both with uniform access and public-access prevention, and a
  partial `gcs` backend whose bucket and prefix arrive from the pipeline.
- `policy/buckets.rego`: four Conftest rules against the plan JSON. No public bindings, mandatory
  `owner` and `env` labels, approved locations only, and no destroy-and-recreate of a bucket without
  `allow-replace = "true"`.
- `.github/workflows/pull-request.yml`: stages 1 to 3. `fmt`, `init`, `validate`, `plan`, the plan
  posted as a sticky pull-request comment, then policy.
- `.github/workflows/apply.yml`: stages 4 and 5. A plan job that saves the plan and prints it in the
  job summary, then an apply job behind the `production` environment's required reviewer.
- `.github/workflows/drift.yml`: stage 6. A daily `plan -detailed-exitcode` that opens an issue on
  exit code 2 and closes it on exit code 0.

## Credentials

None are stored anywhere. GitHub Actions presents an OpenID Connect token; a Workload Identity
Federation provider in the demo project accepts it only when the token names this one repository,
and exchanges it for a short-lived token for the service account `github-actions-tf`. The service
account holds Storage Admin on the project, because creating a bucket needs a project-scoped
permission that no narrower predefined role carries. The runbook says so out loud.

## Why the repository is public

Required reviewers on a GitHub environment are free on a public repository and need GitHub
Enterprise on a private one. The approval gate is stage 4 of the pipeline and the demonstration does
not work without it. The repository holds a project id, which is not a secret, and no credential of
any kind.

## Re-running it

```sh
./bootstrap.sh YOUR_PROJECT_ID frazier-at-cpcc/dsba6190-infrastructure-pipeline   # once; idempotent
./capture.sh   YOUR_PROJECT_ID frazier-at-cpcc/dsba6190-infrastructure-pipeline   # rehearse, never in class
./live-setup.sh YOUR_PROJECT_ID frazier-at-cpcc/dsba6190-infrastructure-pipeline  # before class
```
