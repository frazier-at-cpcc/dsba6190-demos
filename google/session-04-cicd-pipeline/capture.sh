#!/usr/bin/env bash
# Headless rehearsal of the Session 4 CI/CD demo. Do not run this in class.
#
#   ./capture.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]
#
# Pushes repo/ to main, walks a compliant pull request through stages 1 to
# 5, opens a non-compliant pull request and records the stage 3 rejection,
# mutates a bucket out of band and records the stage 6 drift issue, then
# destroys the two buckets. It approves its own deployment through the API,
# which is the one thing a real reviewer would do by hand.
#
# It records real output to capture/NN-step.txt. Every wait is bounded, so
# a wedged workflow fails the script rather than hanging it.
#
# Deliberate residue, so the demo can be re-run in class: the GitHub
# repository, the state bucket, the service account, and the federation.
# The runbook's teardown section lists the commands that remove them.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]}"
REPO="${2:?usage: ./capture.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]}"
WORK="${3:-$HOME/dsba6190-cicd-demo}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$HERE/capture"
STATE_BUCKET="${PROJECT}-tfstate-cicd"
STATE_PREFIX="session-04-cicd"
STAMP="$(date +%H%M)"

mkdir -p "$CAP"
rm -f "$CAP"/[0-9][0-9]-*.txt

say() { printf '\n== %s\n' "$*"; }

# record NN-name -- cmd...   runs cmd, echoes it, and stores the output.
record() {
  local file="$CAP/$1.txt"; shift
  {
    printf '$ %s\n\n' "$*"
    "$@" 2>&1 || printf '\n[exit %s]\n' "$?"
  } | tee "$file"
}

# wait_run <workflow> <branch> <file>   waits for the newest run of a workflow
# on a branch to finish, up to 12 minutes, and records the run summary.
wait_run() {
  local wf="$1" branch="$2" file="$3" id="" i
  for i in $(seq 1 24); do
    id="$(gh run list --repo "$REPO" --workflow "$wf" --branch "$branch" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    [ -n "$id" ] && break
    sleep 5
  done
  [ -n "$id" ] || { echo "no $wf run appeared for $branch"; return 1; }
  for i in $(seq 1 72); do
    local status
    status="$(gh run view "$id" --repo "$REPO" --json status --jq .status)"
    case "$status" in
      completed) break ;;
      waiting)   return 0 ;;
    esac
    sleep 10
  done
  gh run view "$id" --repo "$REPO" 2>&1 | sed -n '1,40p' | tee "$CAP/$file.txt"
  echo "$id"
}

# newest_run <workflow> <branch>
newest_run() {
  gh run list --repo "$REPO" --workflow "$1" --branch "$2" --limit 1 --json databaseId --jq '.[0].databaseId'
}

teardown() {
  set +e
  say "teardown"
  cd "$WORK" 2>/dev/null || return 0
  git checkout -q main 2>/dev/null
  git pull -q 2>/dev/null
  # prevent_destroy is doing its job. Removing it locally, and only locally,
  # is the deliberate act the lecture says destruction should require.
  sed -i '' '/prevent_destroy = true/s/true/false/' main.tf
  terraform init -no-color -reconfigure \
    -backend-config="bucket=$STATE_BUCKET" -backend-config="prefix=$STATE_PREFIX" >/dev/null 2>&1
  terraform destroy -no-color -auto-approve 2>&1 | tail -4 | tee "$CAP/99-teardown.txt"
  git checkout -q -- main.tf
  gcloud storage ls --project "$PROJECT" 2>&1 | tee -a "$CAP/99-teardown.txt"
}
trap teardown EXIT

# ---------------------------------------------------------------- 1. push
say "1. push repo/ to main"
rm -rf "$WORK"
git clone -q "https://github.com/$REPO.git" "$WORK" 2>/dev/null || { mkdir -p "$WORK"; git -C "$WORK" init -q -b main; git -C "$WORK" remote add origin "https://github.com/$REPO.git"; }
cd "$WORK"
git checkout -q -B main
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$HERE/repo/." .
git add -A
git -c user.name="Your Name" -c user.email="you@example.edu" commit -q -m "The pipeline, stages 1 to 6" || true
git push -q -u origin main --force
record 01-push git log --oneline -1

say "the push to main triggers apply.yml; wait for its plan job"
sleep 20
wait_run apply main 02-apply-baseline-run >/dev/null || true
RUN="$(newest_run apply main)"

# ---------------------------------------------------------------- 2. gate
say "2. approve the baseline deployment (the one thing a reviewer does by hand)"
ENV_ID="$(gh api "repos/$REPO/environments/production" --jq .id)"
record 03-pending-deployment gh api "repos/$REPO/actions/runs/$RUN/pending_deployments" \
  --jq '.[] | {environment: .environment.name, current_user_can_approve, waiting_since: .wait_timer_started_at}'
gh api -X POST "repos/$REPO/actions/runs/$RUN/pending_deployments" --input - >/dev/null <<JSON || true
{"environment_ids":[$ENV_ID],"state":"approved","comment":"Approved from capture.sh. In class, a person clicks this."}
JSON
gh run watch "$RUN" --repo "$REPO" --exit-status >/dev/null 2>&1 || true
record 04-apply-baseline gh run view "$RUN" --repo "$REPO" --log --job "$(gh run view "$RUN" --repo "$REPO" --json jobs --jq '.jobs[] | select(.name | startswith("stage 4")) | .databaseId')"
sed -i '' -E 's/^[^\t]*\t[^\t]*\t//' "$CAP/04-apply-baseline.txt"
record 05-buckets-after-baseline gcloud storage ls --project "$PROJECT"

# ---------------------------------------------------------------- 3. compliant PR
say "3. a compliant pull request: add a label"
git checkout -q -b "label-cost-center-$STAMP"
cat >> terraform.tfvars <<'EOF'

extra_labels = {
  cost-center = "dsba6190"
}
EOF
git add -A
git -c user.name="Your Name" -c user.email="you@example.edu" commit -q -m "Label every bucket with its cost center"
git push -q -u origin "label-cost-center-$STAMP"
PR_OK="$(gh pr create --repo "$REPO" --base main --title "Label every bucket with its cost center" \
  --body "Adds cost-center to every bucket. Read the plan the pipeline posts before approving." | grep -oE '[0-9]+$')"
record 06-pr-open gh pr view "$PR_OK" --repo "$REPO" --json number,title,url,headRefName --jq '"#\(.number) \(.title)\n\(.url)\nbranch \(.headRefName)"'

say "stages 1 to 3 run"
wait_run pull-request "label-cost-center-$STAMP" 07-pr-checks-run >/dev/null
record 08-pr-plan-comment bash -c "gh pr view $PR_OK --repo $REPO --comments | sed -n '/Terraform plan for/,\$p' | head -80"
record 09-pr-checks gh pr checks "$PR_OK" --repo "$REPO"

say "merge, then approve the deployment"
gh pr merge "$PR_OK" --repo "$REPO" --squash --delete-branch >/dev/null
sleep 20
wait_run apply main 10-apply-run-waiting >/dev/null || true
RUN="$(newest_run apply main)"
record 11-plan-job-summary gh run view "$RUN" --repo "$REPO" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion // "pending")"'
gh api -X POST "repos/$REPO/actions/runs/$RUN/pending_deployments" --input - >/dev/null <<JSON || true
{"environment_ids":[$ENV_ID],"state":"approved","comment":"Plan read. 0 to add, 2 to change, 0 to destroy. Approved."}
JSON
gh run watch "$RUN" --repo "$REPO" --exit-status >/dev/null 2>&1 || true
record 12-apply-labels gh run view "$RUN" --repo "$REPO" --log --job "$(gh run view "$RUN" --repo "$REPO" --json jobs --jq '.jobs[] | select(.name | startswith("stage 4")) | .databaseId')"
sed -i '' -E 's/^[^\t]*\t[^\t]*\t//' "$CAP/12-apply-labels.txt"
record 13-labels-in-cloud gcloud storage buckets describe "gs://$PROJECT-cicd-scratch" --format="yaml(labels)"

# ---------------------------------------------------------------- 4. non-compliant PR
say "4. a non-compliant pull request: make scratch public"
git checkout -q main && git pull -q
git checkout -q -b "make-scratch-public-$STAMP"
cat > public.tf <<'EOF'
resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.scratch.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
EOF
git add -A
git -c user.name="Your Name" -c user.email="you@example.edu" commit -q -m "Let the public read scratch"
git push -q -u origin "make-scratch-public-$STAMP"
PR_BAD="$(gh pr create --repo "$REPO" --base main --title "Let the public read scratch" \
  --body "A reviewer at 6 PM on a Friday might approve this. Policy will not." | grep -oE '[0-9]+$')"
wait_run pull-request "make-scratch-public-$STAMP" 14-pr-bad-run >/dev/null || true
record 15-pr-bad-comment bash -c "gh pr view $PR_BAD --repo $REPO --comments | sed -n '/Terraform plan for/,/Full plan output/p' | head -40"
record 16-pr-bad-checks gh pr checks "$PR_BAD" --repo "$REPO" || true
gh pr close "$PR_BAD" --repo "$REPO" --delete-branch --comment "Closed. Policy explained why." >/dev/null

# ---------------------------------------------------------------- 5. replace PR
say "5. a destroy-and-recreate without the override label"
git checkout -q main && git pull -q
git checkout -q -b "move-scratch-$STAMP"
python3 - <<'PY'
import re,io
s=open('main.tf').read()
s=s.replace('''resource "google_storage_bucket" "scratch" {
  name                        = "${var.project_id}-cicd-scratch"
  location                    = var.region''','''resource "google_storage_bucket" "scratch" {
  name                        = "${var.project_id}-cicd-scratch"
  location                    = "us-central1"''')
open('main.tf','w').write(s)
PY
git add -A
git -c user.name="Your Name" -c user.email="you@example.edu" commit -q -m "Move scratch to us-central1"
git push -q -u origin "move-scratch-$STAMP"
PR_MOVE="$(gh pr create --repo "$REPO" --base main --title "Move scratch to us-central1" \
  --body "A one-line change. Read the plan symbol." | grep -oE '[0-9]+$')"
wait_run pull-request "move-scratch-$STAMP" 17-pr-move-run >/dev/null || true
record 18-pr-move-comment bash -c "gh pr view $PR_MOVE --repo $REPO --comments | sed -n '/Terraform plan for/,/Full plan output/p' | head -40"
gh pr close "$PR_MOVE" --repo "$REPO" --delete-branch --comment "Closed. A location change is a replace, and nobody said so." >/dev/null

# ---------------------------------------------------------------- 6. drift
say "6. drift: change a label in the cloud, then run the scheduled plan by hand"
git checkout -q main && git pull -q
record 19-drift-mutation gcloud storage buckets update "gs://$PROJECT-cicd-scratch" --update-labels env=prod-by-accident --project "$PROJECT"
gh workflow run drift --repo "$REPO" >/dev/null
sleep 15
wait_run drift main 20-drift-run >/dev/null || true
record 21-drift-issue bash -c "gh issue list --repo $REPO --label drift --state open --json number,title,url --jq '.[] | \"#\(.number) \(.title)\n\(.url)\"'; n=\$(gh issue list --repo $REPO --label drift --state open --json number --jq '.[0].number'); gh issue view \$n --repo $REPO --json body --jq .body | head -40"

say "reconcile: reality loses, main wins"
record 22-drift-reconcile gcloud storage buckets update "gs://$PROJECT-cicd-scratch" --update-labels env=dev --project "$PROJECT"
gh workflow run drift --repo "$REPO" >/dev/null
sleep 15
wait_run drift main 23-drift-run-clean >/dev/null || true
record 24-drift-issue-closed gh issue list --repo "$REPO" --label drift --state closed --limit 1 --json number,title,state --jq '.[] | "#\(.number) \(.title) \(.state)"'

say "done. teardown runs on exit."
