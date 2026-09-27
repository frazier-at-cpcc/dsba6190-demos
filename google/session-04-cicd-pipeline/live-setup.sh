#!/usr/bin/env bash
# Stage the Session 4 CI/CD demo. Run this BEFORE class, not during.
#
#   ./live-setup.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]
#
# Makes sure main on GitHub matches repo/, that the two buckets exist and
# match main, and that three branches are ready to become pull requests in
# front of the room:
#
#   demo/label-cost-center    compliant. Stages 1 to 5, end to end.
#   demo/make-scratch-public  rejected by policy rule 1.
#   demo/move-scratch         rejected by policy rule 4, a replace.
#
# It applies the baseline with the instructor's own credentials so that the
# room does not wait for a first apply. It does not open any pull request
# and it does not destroy anything.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]}"
REPO="${2:?usage: ./live-setup.sh <PROJECT_ID> <GITHUB_OWNER/REPO> [WORKDIR]}"
WORK="${3:-$HOME/dsba6190-live-demo-04-cicd}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_BUCKET="${PROJECT}-tfstate-cicd"
STATE_PREFIX="session-04-cicd"

commit() { git -c user.name="Your Name" -c user.email="you@example.edu" commit -q "$@"; }

rm -rf "$WORK"
git clone -q "https://github.com/$REPO.git" "$WORK"
cd "$WORK"
git checkout -q -B main

# main must equal repo/. If it does not, push it and let apply.yml run; the
# instructor approves that one from the browser before class.
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$HERE/repo/." .
if ! git diff --quiet || [ -n "$(git status --porcelain)" ]; then
  git add -A
  commit -m "Reset main to the reference pipeline"
  git push -q origin main
  echo "main was reset and pushed. Approve the resulting apply under Actions before class."
fi

# Baseline applied with the instructor's credentials, so the room starts
# from two existing buckets and every plan in class is a change, not a create.
terraform init -no-color -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="prefix=$STATE_PREFIX" >/dev/null
terraform apply -no-color -auto-approve >/dev/null
gcloud storage buckets update "gs://$PROJECT-cicd-scratch" --update-labels env=dev --project "$PROJECT" >/dev/null

# Three branches, pushed, each one `gh pr create` away.
git push -q origin --delete demo/label-cost-center demo/make-scratch-public demo/move-scratch 2>/dev/null || true

git checkout -q -b demo/label-cost-center main
cat >> terraform.tfvars <<'EOF'

extra_labels = {
  cost-center = "dsba6190"
}
EOF
git add -A && commit -m "Label every bucket with its cost center"
git push -q -u origin demo/label-cost-center

git checkout -q -b demo/make-scratch-public main
cat > public.tf <<'EOF'
resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.scratch.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
EOF
git add -A && commit -m "Let the public read scratch"
git push -q -u origin demo/make-scratch-public

git checkout -q -b demo/move-scratch main
python3 - <<'PY'
s = open('main.tf').read()
s = s.replace('''  name                        = "${var.project_id}-cicd-scratch"
  location                    = var.region''', '''  name                        = "${var.project_id}-cicd-scratch"
  location                    = "us-central1"''')
open('main.tf', 'w').write(s)
PY
git add -A && commit -m "Move scratch to us-central1"
git push -q -u origin demo/move-scratch

git checkout -q main

# Read by the LOAD cell of prep.ipynb and demo.ipynb. Excluded from git so no
# commit in the clone can pick it up.
cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export REPO="$REPO"
export STATE_BUCKET="$STATE_BUCKET"
export STATE_PREFIX="$STATE_PREFIX"
export LAKE_BUCKET="$PROJECT-cicd-lake"
export SCRATCH_BUCKET="$PROJECT-cicd-scratch"
export WORKDIR="$WORK"
ENVEOF
echo "env.sh" >> "$WORK/.git/info/exclude"

# Any drift issue left from a rehearsal would spoil step 6.
for n in $(gh issue list --repo "$REPO" --label drift --state open --json number --jq '.[].number'); do
  gh issue close "$n" --repo "$REPO" --comment "Closed before class." >/dev/null
done

cat <<DONE

  Staged for the live demo.

  Working directory   $WORK
  Repository          https://github.com/$REPO
  Buckets             $PROJECT-cicd-lake, $PROJECT-cicd-scratch, applied and matching main

  Branches ready to open as pull requests, from $WORK:

    gh pr create --base main --head demo/label-cost-center   --fill
    gh pr create --base main --head demo/make-scratch-public --fill
    gh pr create --base main --head demo/move-scratch        --fill

  Browser tabs to have open:
    https://github.com/$REPO/pulls
    https://github.com/$REPO/actions
    https://github.com/$REPO/issues?q=label%3Adrift
    https://console.cloud.google.com/storage/browser?project=$PROJECT

  Verify now:  gh run list --repo $REPO --limit 3

  Tear down after class: see RUNBOOK.md, section Teardown.

DONE
