#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 4 CI/CD demonstration.

    python3 build-notebook.py

    prep.ipynb   before you start: stage the repository and the baseline, verify
    demo.ipynb   steps 1 to 7, with the teardown as step 7

Commands only, on the Bash kernel. The walkthrough is in RUNBOOK.md.

Each pull request is created from its cell, its number is kept in $PR, and
`gh pr view --web` opens it. The approval at step 3 stays a click in the
browser, and the notebook opens the run page for it. The drift label edit at
step 6 can be made in the Console, and the notebook carries the gcloud
equivalent. The retirement commands in the runbook's teardown are left out on
purpose, because they delete the repository and the federation that a second
run needs.

Every wait on GitHub Actions is a bounded loop in find_run and wait_run,
defined in the demo's second cell. find_run gives up after two minutes if no
run appears; wait_run gives up after fifteen, and prints the browser
instruction once when a run stops at the production gate. Neither approves
anything: the approval stays a click in the browser.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-04-cicd"
REPO = "frazier-at-cpcc/dsba6190-infrastructure-pipeline"


def notebook(name, parts):
    cells = []
    for kind, text in parts:
        cell = {"cell_type": kind, "metadata": {}, "id": f"{name}-{len(cells):03d}",
                "source": text.strip("\n").splitlines(keepends=True)}
        if kind == "code":
            cell.update(execution_count=None, outputs=[])
        cells.append(cell)
    nb = {"cells": cells,
          "metadata": {"kernelspec": {"display_name": "Bash", "language": "bash", "name": "bash"},
                       "language_info": {"name": "bash", "codemirror_mode": "shell",
                                         "file_extension": ".sh", "mimetype": "text/x-sh"}},
          "nbformat": 4, "nbformat_minor": 5}
    (HERE / f"{name}.ipynb").write_text(json.dumps(nb, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {name}.ipynb: {len(cells)} cells, "
          f"{sum(c['cell_type'] == 'code' for c in cells)} commands")


def md(text):
    return ("markdown", text)


def sh(text):
    return ("code", text)


def open_pr(branch):
    return sh(f"URL=$(gh pr create --base main --head {branch} --fill) && PR=${{URL##*/}}"
              ' && echo "pull request $PR  $URL"\n'
              'gh pr view "${PR:?}" --web')


# Stages 1 to 3 on the pull request, then the sticky comment without the full plan.
PR_CHECKS = sh('RUN=$(find_run pull-request "$(gh pr view "${PR:?}" --json headRefOid --jq .headRefOid)")'
               ' && wait_run "$RUN"\n'
               'gh pr view "$PR" --json comments \\\n'
               '  --jq \'.comments[] | select(.body | contains("Terraform plan for")) | .body\' \\\n'
               "  | sed '/<details>/,$d'")


def drift_run():
    return ('BEFORE=$(gh run list --workflow drift --limit 1 --json databaseId --jq \'.[0].databaseId // 0\')\n'
            'gh workflow run drift\n'
            'RUN=$(find_run drift "" "$BEFORE") && wait_run "$RUN"\n'
            'gh issue list --label drift --state all --limit 3')


HELPERS = sh(r'''
# find_run WORKFLOW [COMMIT] [NEWER_THAN]  prints the run id once GitHub has created the run
find_run() {
  local start=$SECONDS id args=(--workflow "$1" --limit 1 --json databaseId)
  [ -n "${2:-}" ] && args+=(--commit "$2")
  echo "waiting for the $1 run to appear" >&2
  until id=$(gh run list "${args[@]}" --jq ".[] | select(.databaseId > ${3:-0}) | .databaseId") && [ -n "$id" ]; do
    if (( SECONDS - start > 120 )); then echo "No $1 run after 120 s. Look at the Actions tab." >&2; return 1; fi
    sleep 3
  done
  echo "$id"
}

# wait_run RUN_ID  returns when the run completes; says once when it waits at the gate
wait_run() {
  local start=$SECONDS told="" status=""
  until status=$(gh run view "${1:?}" --json status --jq .status) && [ "$status" = completed ]; do
    if [ "$status" = waiting ] && [ -z "$told" ]; then
      echo "Run $1 is waiting at the production gate. In the browser: Review deployments, tick production, Approve and deploy."
      told=1
    fi
    if (( SECONDS - start > 900 )); then echo "Run $1 still $status after 15 minutes. Look at it in the browser."; return 1; fi
    sleep 5
  done
  gh run view "$1" --json conclusion,url --jq '"run \(.conclusion) in \(.url)"'
}
echo "helpers loaded"
''')


LOAD = sh(f'source {WORKDIR}/env.sh && cd "$WORKDIR" && echo "$PROJECT" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
NEWEST_APPLY = "gh run list --workflow apply --limit 1 --json databaseId --jq '.[0].databaseId'"

notebook("prep", [
    md("# Session 4 CI/CD · Before you start"),
    md("## Stage\n\n"
       "Replace `YOUR_PROJECT_ID` and the repository in the next cell with your own project "
       "and your own `OWNER/REPO`."),
    sh(f"./live-setup.sh YOUR_PROJECT_ID {REPO}"),
    LOAD,
    md("## Verify"),
    sh('gh run list --repo "$REPO" --limit 3'),
    sh('gh workflow list --repo "$REPO"'),
    sh('gcloud storage ls --project "$PROJECT" | grep cicd'),
])

notebook("demo", [
    md("# Session 4 CI/CD · The infrastructure pipeline, worked\n\n"
       "A GitHub Actions pipeline delivers two Cloud Storage buckets through plan, policy, "
       "approval, apply and drift detection."),
    LOAD,
    HELPERS,

    md("## Step 1 · The repository, and who it trusts"),
    sh("gh variable list"),
    sh('gcloud iam workload-identity-pools providers describe github \\\n'
       '  --workload-identity-pool github-actions --location global \\\n'
       '  --project "$PROJECT" --format "value(attributeCondition)"'),

    md("## Step 2 · A compliant pull request"),
    open_pr("demo/label-cost-center"),
    PR_CHECKS,

    md("## Step 3 · Merge, and meet the gate"),
    sh('gh pr merge "${PR:?}" --squash --delete-branch'),
    sh('RUN=$(find_run apply "$(gh pr view "${PR:?}" --json mergeCommit --jq .mergeCommit.oid)")'
       ' && gh run view "$RUN" --web'),
    sh('wait_run "${RUN:?}"'),
    sh('gcloud storage buckets describe "gs://$SCRATCH_BUCKET" --format "yaml(labels)"'),

    md("## Step 4 · A public bucket"),
    open_pr("demo/make-scratch-public"),
    PR_CHECKS,
    sh('gh pr close "${PR:?}" --delete-branch'),

    md("## Step 5 · The replace nobody announced"),
    open_pr("demo/move-scratch"),
    PR_CHECKS,
    sh('gh pr close "${PR:?}" --delete-branch'),

    md("## Step 6 · Drift"),
    sh('# The same label edit the runbook makes in the Console\n'
       'gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=prod-by-accident --project "$PROJECT"'),
    sh(drift_run()),
    sh('gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=dev --project "$PROJECT"'),
    sh(drift_run()),

    md("## Step 7 · Teardown"),
    sh('cd "${WORKDIR:?}"\ngit checkout main && git pull\n'
       "sed -i '' '/prevent_destroy = true/s/true/false/' main.tf"),
    sh('terraform init -reconfigure \\\n'
       '  -backend-config="bucket=${STATE_BUCKET:?}" \\\n'
       '  -backend-config="prefix=${STATE_PREFIX:?}"'),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh("git checkout -- main.tf"),
    sh('# The daily drift plan would report the destroyed buckets every morning. live-setup.sh enables it again.\n'
       'gh workflow disable drift'),
    sh('gcloud storage ls --project "$PROJECT" | grep cicd\n'
       'gh pr list --state open\n'
       'gh issue list --label drift --state open\n'
       'git ls-remote --heads origin'),
])
