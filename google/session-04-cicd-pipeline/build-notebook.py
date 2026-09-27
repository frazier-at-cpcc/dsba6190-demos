#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 4 CI/CD demonstration.

    python3 build-notebook.py

    prep.ipynb   T minus 30: stage the repository and the baseline, verify
    demo.ipynb   steps 1 to 6, teardown included

Commands only, on the Bash kernel. What to say is in RUNBOOK.md.

The runbook opens each pull request with `gh pr create --web`, which opens a
compose page and waits for a click. Here the pull request is created from the
cell, its number is kept in $PR, and `gh pr view --web` opens it. The
approval at step 3 and the drift label edit at step 6 stay in the browser in
the runbook; the notebook opens the run page for the first and carries the
gcloud equivalent of the second. The retirement commands in the runbook's
teardown are left out on purpose, because they delete the repository and the
federation the demonstration needs next term.
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
    return sh(f"gh pr create --base main --head {branch} --fill\n"
              f"PR=$(gh pr view {branch} --json number --jq .number); echo \"pull request $PR\"\n"
              'gh pr view "$PR" --web')


LOAD = sh(f'source {WORKDIR}/env.sh && cd "$WORKDIR" && echo "$PROJECT" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
NEWEST_APPLY = "gh run list --workflow apply --limit 1 --json databaseId --jq '.[0].databaseId'"

notebook("prep", [
    md("# Session 4 CI/CD · Before class"),
    md("## T minus 30 · Stage"),
    sh(f"./live-setup.sh YOUR_PROJECT_ID {REPO}"),
    LOAD,
    md("## T minus 25 · Verify"),
    sh('gh run list --repo "$REPO" --limit 3'),
    sh('gcloud storage ls --project "$PROJECT" | grep cicd'),
])

notebook("demo", [
    md("# Session 4 CI/CD · The infrastructure pipeline, worked\n\n"
       "Two Cloud Storage buckets delivered through plan, policy, approval, apply and drift "
       "detection on GitHub Actions."),
    LOAD,

    md("## Step 1 · The repository, and who it trusts"),
    sh("gh variable list"),
    sh('gcloud iam workload-identity-pools providers describe github \\\n'
       '  --workload-identity-pool github-actions --location global \\\n'
       '  --project "$PROJECT" --format "value(attributeCondition)"'),

    md("## Step 2 · A compliant pull request"),
    open_pr("demo/label-cost-center"),

    md("## Step 3 · Merge, and meet the gate"),
    sh('gh pr merge "${PR:?}" --squash --delete-branch'),
    sh(f'gh run view "$({NEWEST_APPLY})" --web'),
    sh('gcloud storage buckets describe "gs://$SCRATCH_BUCKET" --format "yaml(labels)"'),

    md("## Step 4 · A public bucket"),
    open_pr("demo/make-scratch-public"),
    sh('gh pr close "${PR:?}"'),

    md("## Step 5 · The replace nobody announced"),
    open_pr("demo/move-scratch"),
    sh('gh pr close "${PR:?}"'),

    md("## Step 6 · Drift"),
    sh('# The same label edit the runbook makes in the Console\n'
       'gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=prod-by-accident --project "$PROJECT"'),
    sh("gh workflow run drift"),
    sh("gh issue list --label drift --state all --limit 3"),
    sh('gcloud storage buckets update "gs://$SCRATCH_BUCKET" --update-labels env=dev --project "$PROJECT"\n'
       'gh workflow run drift'),
    sh("gh issue list --label drift --state all --limit 3"),

    md("## After class"),
    sh('cd "${WORKDIR:?}"\ngit checkout main && git pull\n'
       "sed -i '' '/prevent_destroy = true/s/true/false/' main.tf"),
    sh('terraform init -reconfigure \\\n'
       '  -backend-config="bucket=${STATE_BUCKET:?}" \\\n'
       '  -backend-config="prefix=${STATE_PREFIX:?}"'),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh("git checkout -- main.tf"),
])
