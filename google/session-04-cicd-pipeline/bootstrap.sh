#!/usr/bin/env bash
# One-time setup for the Session 4 CI/CD demo. Idempotent: run it again and
# it changes nothing that already exists.
#
#   ./bootstrap.sh <PROJECT_ID> <GITHUB_OWNER/REPO>
#
# Google Cloud side: enables the APIs, creates the versioned state bucket,
# creates the service account the pipeline runs as, and federates GitHub's
# OpenID Connect tokens to it for exactly one repository. No key is created
# or downloaded, ever.
#
# GitHub side: creates the public repository if it is missing, sets the four
# Actions variables the workflows read, creates the `production` environment
# with you as the required reviewer, and creates the `drift` label.
# The repository is public because required reviewers on an environment need
# a paid plan on a private repository, and the demo holds no secret.
#
# It does not push code. capture.sh and live-setup.sh do that.

set -euo pipefail

PROJECT="${1:?usage: ./bootstrap.sh <PROJECT_ID> <GITHUB_OWNER/REPO>}"
REPO="${2:?usage: ./bootstrap.sh <PROJECT_ID> <GITHUB_OWNER/REPO>}"

REGION="us-east1"
POOL="github-actions"
PROVIDER="github"
SA_NAME="github-actions-tf"
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
STATE_BUCKET="${PROJECT}-tfstate-cicd"
STATE_PREFIX="session-04-cicd"

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"

echo "== APIs"
gcloud services enable \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  storage.googleapis.com cloudresourcemanager.googleapis.com \
  --project "$PROJECT" --quiet

echo "== State bucket gs://$STATE_BUCKET"
if ! gcloud storage buckets describe "gs://$STATE_BUCKET" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project "$PROJECT" --location "$REGION" \
    --uniform-bucket-level-access --public-access-prevention
fi
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning --project "$PROJECT" >/dev/null

echo "== Service account $SA"
if ! gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --project "$PROJECT" \
    --display-name "GitHub Actions · Terraform" \
    --description "Runs terraform plan and apply from GitHub Actions through Workload Identity Federation"
fi
# Creating buckets needs storage.buckets.create at project scope, which no
# narrower predefined role carries. Storage Admin is the honest minimum here,
# and the runbook says so.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member "serviceAccount:$SA" --role roles/storage.admin \
  --condition=None --quiet >/dev/null

echo "== Workload Identity pool $POOL"
if ! gcloud iam workload-identity-pools describe "$POOL" --location global --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL" \
    --project "$PROJECT" --location global \
    --display-name "GitHub Actions"
fi

echo "== Provider $PROVIDER, trusting only $REPO"
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER" \
      --workload-identity-pool "$POOL" --location global --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project "$PROJECT" --location global \
    --workload-identity-pool "$POOL" \
    --display-name "GitHub" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition "assertion.repository == '$REPO'"
else
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" \
    --project "$PROJECT" --location global \
    --workload-identity-pool "$POOL" \
    --attribute-condition "assertion.repository == '$REPO'" >/dev/null
fi

WIF_PROVIDER="projects/${NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
PRINCIPAL_SET="principalSet://iam.googleapis.com/projects/${NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${REPO}"

echo "== Let $REPO impersonate $SA"
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project "$PROJECT" \
  --role roles/iam.workloadIdentityUser \
  --member "$PRINCIPAL_SET" --quiet >/dev/null

echo "== GitHub repository $REPO"
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" --public \
    --description "DSBA 6190 · Session 4 · the infrastructure pipeline, worked" >/dev/null
fi

echo "== Actions variables"
gh variable set WIF_PROVIDER      --repo "$REPO" --body "$WIF_PROVIDER"
gh variable set TF_SERVICE_ACCOUNT --repo "$REPO" --body "$SA"
gh variable set TF_STATE_BUCKET   --repo "$REPO" --body "$STATE_BUCKET"
gh variable set TF_STATE_PREFIX   --repo "$REPO" --body "$STATE_PREFIX"

echo "== Environment production, reviewer $(gh api user --jq .login)"
UID_GH="$(gh api user --jq .id)"
gh api -X PUT "repos/$REPO/environments/production" --input - >/dev/null <<JSON
{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":$UID_GH}],"deployment_branch_policy":null}
JSON

echo "== Label drift"
gh label create drift --repo "$REPO" --color D93F0B \
  --description "Opened by the scheduled plan when reality differs from main" --force >/dev/null

cat <<DONE

  Bootstrapped.

  Project            $PROJECT ($NUMBER)
  State bucket       gs://$STATE_BUCKET   prefix $STATE_PREFIX
  Service account    $SA
  WIF provider       $WIF_PROVIDER
  Trusted principal  $PRINCIPAL_SET
  Repository         https://github.com/$REPO
  Environment        production, required reviewer $(gh api user --jq .login)

  Nothing here is billable beyond the state bucket, which holds kilobytes.

  Next: ./capture.sh $PROJECT $REPO   to record a headless run
        ./live-setup.sh $PROJECT $REPO to stage the walkthrough

DONE
