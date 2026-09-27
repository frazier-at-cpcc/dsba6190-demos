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

rm -rf "${WORK:?}"
git clone -q "https://github.com/$REPO.git" "$WORK"
cd "$WORK"
git checkout -q -B main
# The provider lock file is written by the local init below. Kept out of every
# commit so the room sees only the lines each pull request is about.
printf 'env.sh\n.terraform.lock.hcl\n' >> "$WORK/.git/info/exclude"

# main must equal repo/.
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$HERE/repo/." .

# Baseline applied with the instructor's credentials, so the room starts
# from two existing buckets and every plan in class is a change, not a create.
# Applied before main is pushed, so no runner plans against a state that is
# about to change underneath it.
terraform init -no-color -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="prefix=$STATE_PREFIX" >/dev/null
# A bucket that exists but is missing from state (state lost, or a teardown
# that stopped halfway) would make apply fail with 409. Adopt it instead.
for r in lake scratch; do
  if ! terraform state list 2>/dev/null | grep -qx "google_storage_bucket.$r" \
     && gcloud storage buckets describe "gs://$PROJECT-cicd-$r" --project "$PROJECT" >/dev/null 2>&1; then
    echo "gs://$PROJECT-cicd-$r exists but is not in state. Importing it."
    terraform import -no-color "google_storage_bucket.$r" "$PROJECT-cicd-$r" >/dev/null
  fi
done
terraform apply -no-color -auto-approve >/dev/null
gcloud storage buckets update "gs://$PROJECT-cicd-scratch" --update-labels env=dev --project "$PROJECT" >/dev/null

# The reset commit carries [skip ci]. An apply run for it would wait at the
# production gate, and while it waits it holds the terraform-state
# concurrency group, so every pull-request run in class would queue behind it.
# The baseline is already applied above, so the run would have nothing to do.
if ! git diff --quiet || [ -n "$(git status --porcelain)" ]; then
  git add -A
  commit -m "Reset main to the reference pipeline [skip ci]"
  git push -q origin main
  echo "main was reset to repo/ and pushed without triggering apply."
fi

# Three branches, pushed, each one `gh pr create` away.
# One branch per push: a multi-ref delete fails as a whole when any one ref is
# already gone, which left a stale branch behind and broke the push below.
# Deleting a branch also closes any pull request still open from it.
for b in demo/label-cost-center demo/make-scratch-public demo/move-scratch; do
  if git ls-remote --exit-code --heads origin "$b" >/dev/null; then
    git push -q origin --delete "$b"
  fi
done

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

# The after-class teardown disables the scheduled drift workflow, because
# against destroyed buckets it would open an issue every morning.
gh workflow enable drift --repo "$REPO" 2>/dev/null || true

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
