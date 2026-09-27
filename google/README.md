# DSBA 6190 live demonstrations · Google Cloud

This folder holds the live demonstrations from DSBA 6190, Cloud Computing for Data Analysis. Each
one follows a fictional Charlotte business through a sequence of real work on Google Cloud, and each
one ends by deleting everything it created.

Use them in two ways. **Read them** to see each step of the work and its real result. Every
demonstration keeps the output of every command in its `capture/` folder, so nothing needs to run.
**Run them** on your own Google Cloud account if you want to repeat the work yourself.

## Running a demonstration costs you money

Running any of these creates billable resources in your own project, on your own billing account.
The course does not pay for it and does not reimburse it. Each walkthrough states what the recorded
run cost. Most cost under one dollar. The Data Fusion, GKE and Dataflow demonstrations cost more if
their resources are left running.

1. Use a project you created for this purpose, never a shared or production project.
2. Set a budget with an alert before you start. A budget alerts you. It does not stop spending.
3. Run the teardown step at the end of every demonstration, then run its verification cell and
   confirm it lists nothing.
4. Every command that deletes something names its target as `${NAME:?}`, so an empty variable
   refuses to run instead of deleting the wrong thing. Do not remove those guards.
5. Check your project's quotas first. Each Spark batch in the Session 10 demonstration holds 12
   vCPUs, so it needs a `CPUS_ALL_REGIONS` quota of at least 12, and new accounts sometimes start
   lower. The Quotas page under IAM and Admin shows the current limit.

## What you need

- A Google Cloud project with billing enabled, and the Google Cloud CLI (`gcloud`, `bq`),
  authenticated with `gcloud auth login` and `gcloud auth application-default login`
- `jq`, and Python 3.11 or later. [`uv`](https://docs.astral.sh/uv/) runs the Python tools that need
  extra packages
- Terraform 1.5 or later for Sessions 3 to 5
- Jupyter with the Bash kernel (`pip install bash_kernel && python -m bash_kernel.install`), or
  VS Code with the Jupyter extension

## How each demonstration is organized

| File | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the real figures and what each step shows |
| `prep.ipynb` | Staging. Replace `YOUR_PROJECT_ID` in its first cell, then run it |
| `demo.ipynb` | Every command of the demonstration, in order, teardown last |
| `live-setup.sh` | What `prep.ipynb` runs. It creates resources and never deletes them |
| `capture/` | The real output of every command from the recorded run |
| `capture.sh` | The script that recorded `capture/`. It stages, runs and deletes everything in one pass |

Open `demo.ipynb` on the Bash kernel. In VS Code choose **Select Kernel**, **Jupyter Kernel**,
**Bash**. The Python kernel produces syntax errors on every cell.

## The demonstrations

| Session | Topic | Demonstration | Guide |
|---|---|---|---|
| 1 | Cloud Foundations | [One nightly job, three ways](session-01-one-job-three-ways/) | [Walkthrough](session-01-one-job-three-ways/RUNBOOK.md) |
| 2 | IAM, Networking and Security | [Grant it wrong, then fix it](session-02-grant-it-wrong-then-fix-it/) | [Walkthrough](session-02-grant-it-wrong-then-fix-it/RUNBOOK.md) |
| 3 | Infrastructure as Code | [Monolith to module](session-03-monolith-to-module/) | [Walkthrough](session-03-monolith-to-module/RUNBOOK.md) |
| 4 | Terraform State and Automation | [Migrate state, then break it](session-04-migrate-state-then-break-it/) | [Walkthrough](session-04-migrate-state-then-break-it/RUNBOOK.md) |
| 4 | Terraform State and Automation | [An infrastructure pipeline with four gates](session-04-cicd-pipeline/) | [Walkthrough](session-04-cicd-pipeline/RUNBOOK.md) |
| 5 | Cloud Storage and Data Lakes | [Build and harden a lake](session-05-build-and-harden-a-lake/) | [Walkthrough](session-05-build-and-harden-a-lake/RUNBOOK.md) |
| 6 | Ingestion and Integration | [A batch pipeline, then break it](session-06-batch-pipeline-then-break-it/) | [Walkthrough](session-06-batch-pipeline-then-break-it/RUNBOOK.md) |
| 7 | Warehousing with BigQuery | [Make the cost visible, then govern it](session-07-make-the-cost-visible/) | [Walkthrough](session-07-make-the-cost-visible/RUNBOOK.md) |
| 8 | Containers and Kubernetes | [Build, deploy, break and move](session-08-build-deploy-break-move/) | [Walkthrough](session-08-build-deploy-break-move/RUNBOOK.md) |
| 10 | Distributed Processing | [Read a plan, find the skew](session-10-read-a-plan-find-the-skew/) | [Walkthrough](session-10-read-a-plan-find-the-skew/RUNBOOK.md) |
| 11 | Streaming | [Build a stream, then break it](session-11-build-a-stream-then-break-it/) | [Walkthrough](session-11-build-a-stream-then-break-it/RUNBOOK.md) |
| 12 | Machine Learning in BigQuery | Build a leaky model, then catch it | Released 12 November |
| 13 | Vertex AI | [Train, register and serve](session-13-vertex-train-register-serve/) | [Walkthrough](session-13-vertex-train-register-serve/RUNBOOK.md) |
| 14 | Production Readiness and FinOps | [Green status, wrong data](session-14-green-status-wrong-data/) | [Walkthrough](session-14-green-status-wrong-data/RUNBOOK.md) |

Session 9 is the midterm, and it is the only session without a demonstration.
