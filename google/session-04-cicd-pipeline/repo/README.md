# DSBA 6190 · infrastructure pipeline

This repository is the worked example for Session 4 of DSBA 6190 at UNC Charlotte. It deploys two
Cloud Storage buckets with Terraform through the six-stage delivery pipeline that the session
describes.

| Stage | Where it runs | What it does |
|---|---|---|
| 1 | `pull-request.yml` | `fmt -check`, `init`, `validate` |
| 2 | `pull-request.yml` | `plan`, posted as a comment on the pull request |
| 3 | `pull-request.yml` | Conftest rules in `policy/` reject the plan without a human |
| 4 | `apply.yml` | The `production` environment requires a reviewer before the apply job starts |
| 5 | `apply.yml` | `apply` of the saved plan, by a service account through Workload Identity Federation |
| 6 | `drift.yml` | A scheduled `plan -detailed-exitcode`. Exit code 2 opens an issue |

No credential is stored in this repository or in its secrets. GitHub Actions presents an OpenID
Connect token to Google Cloud, which exchanges it for a short-lived token for the service account
`github-actions-tf`. The federation trusts only this repository.

## The four policy rules

1. No IAM binding to `allUsers` or `allAuthenticatedUsers`.
2. Every bucket carries the labels `owner` and `env`.
3. Every bucket lives in an approved location.
4. No bucket is destroyed and recreated unless the change carries `allow-replace = "true"`.

Rule 1 has a second layer. Every bucket also sets `public_access_prevention = "enforced"`, so the
platform refuses the binding even when someone bypasses the pipeline. The pipeline rule can say
which line broke. The platform rule cannot be bypassed. A delivery process wants both.

## Try it

Open a pull request that changes `terraform.tfvars`. Read the plan the workflow posts. Merge it,
then approve the deployment under **Actions**. Then open a pull request that adds the following
resource, and read the reason the check fails.

```hcl
resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.scratch.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
```
