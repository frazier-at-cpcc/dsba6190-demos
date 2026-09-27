#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 4 state demonstration.

    python3 build-notebook.py

    prep.ipynb   T minus 30: stage and apply the baseline, verify
    demo.ipynb   the hour, steps 1 to 11, teardown included

Commands only, on the Bash kernel. What to say is in RUNBOOK.md.

A notebook cell cannot answer a yes prompt, so every apply and destroy
carries -auto-approve and the migration carries -force-copy. Steps 5 and 6
need two terminals in the runbook; here the first terminal's apply runs as a
background job writing to a log, and the following cells run the second
terminal's commands and then show the log.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-04"


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


LOAD = sh(f'source {WORKDIR}/env.sh && cd "$WORKDIR" && echo "$PROJECT" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
GREP_PW = "grep -o '\"result\": \"[^\"]*\"'"
WAIT_APPLY = ('while kill -0 "$(cat apply.pid)" 2>/dev/null; do sleep 5; done\n'
              'tail -4 apply.log')

notebook("prep", [
    md("# Session 4 · Before class"),
    md("## T minus 30 · Stage and apply the baseline"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## T minus 25 · Verify"),
    sh("terraform plan"),
])

notebook("demo", [
    md("# Session 4 · Migrate state, then break it\n\n"
       "A bucket, a topic and a generated password on local state, moved to a versioned "
       "backend and then broken eight ways."),
    LOAD,

    md("## Step 1 · Read the state you already have"),
    sh("terraform state list"),
    sh("terraform output"),
    sh("terraform state show random_password.db_admin"),
    sh(f"{GREP_PW} terraform.tfstate"),

    md("## Step 2 · Bootstrap the state bucket, with versioning"),
    sh('gcloud storage buckets create "gs://$STATE_BUCKET" \\\n'
       '  --project "$PROJECT" --location=US-EAST1 \\\n'
       '  --uniform-bucket-level-access --public-access-prevention\n\n'
       'gcloud storage buckets update "gs://$STATE_BUCKET" \\\n'
       '  --project "$PROJECT" --versioning'),
    sh('gcloud storage buckets describe "gs://$STATE_BUCKET" \\\n'
       '  --project "$PROJECT" \\\n'
       '  --format="yaml(name,location,default_storage_class,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"'),

    md("## Step 3 · The backend block, and the migration"),
    sh("cp backend.tf.staged backend.tf\ncat backend.tf"),
    sh("terraform init -migrate-state -force-copy"),
    sh('gcloud storage ls -r "gs://$STATE_BUCKET" --project "$PROJECT"'),
    sh(f'gcloud storage cat "$STATE_OBJECT" --project "$PROJECT" \\\n  | {GREP_PW}'),

    md("## Step 4 · Plan says no changes"),
    sh("terraform plan"),
    sh(f"ls -l terraform.tfstate*\n{GREP_PW} terraform.tfstate.backup"),
    sh('rm -f -- "${WORKDIR:?}/terraform.tfstate" "${WORKDIR:?}/terraform.tfstate.backup"'),

    md("## Step 5 · Two terminals, one lock"),
    sh("cp main.tf.sleep main.tf\ngrep -n -A6 'resource \"time_sleep\"' main.tf"),
    sh('# First terminal\n'
       'terraform apply -auto-approve -no-color > apply.log 2>&1 &\n'
       'echo $! > apply.pid; echo "apply started"'),
    sh('# Second terminal\n'
       'sleep 20; tail -3 apply.log\n'
       'terraform plan'),
    sh(WAIT_APPLY),

    md("## Step 6 · The crashed run, and force-unlock"),
    sh('terraform apply -auto-approve -no-color -replace=time_sleep.slow_apply > apply.log 2>&1 &\n'
       'echo $! > apply.pid; echo "apply started"'),
    sh('sleep 20; tail -3 apply.log\n'
       'kill -9 "$(cat apply.pid)"; pkill -9 -f terraform-provider-time; echo "killed"'),
    sh("terraform plan -no-color 2>&1 | tee plan-lock.log"),
    sh("LOCK_ID=$(grep -Eo 'ID: *[0-9a-f-]+' plan-lock.log | head -1 | awk '{print $2}')\n"
       'terraform force-unlock -force "${LOCK_ID:?}"'),
    sh("terraform plan"),

    md("## Step 7 · Versioning is the undo"),
    sh("GOOD_GEN=$(gcloud storage objects describe \"$STATE_OBJECT\" --project \"$PROJECT\" --format='value(generation)')\n"
       'echo "generation before the delete: $GOOD_GEN"\n'
       'gcloud storage rm "gs://${STATE_BUCKET:?}/envs/dev/default.tfstate" \\\n'
       '  --project "${PROJECT:?}"'),
    sh("terraform plan"),
    sh('gcloud storage ls --all-versions --long \\\n'
       '  "gs://$STATE_BUCKET/envs/dev/" --project "$PROJECT"'),
    sh('gcloud storage cp \\\n'
       '  "$STATE_OBJECT#${GOOD_GEN:?}" \\\n'
       '  "$STATE_OBJECT" \\\n'
       '  --project "$PROJECT"'),
    sh("terraform plan"),

    md("## Step 8 · Import what somebody built by hand"),
    sh("cp legacy.tf.guess legacy.tf\ncat legacy.tf"),
    sh('terraform import google_storage_bucket.legacy \\\n'
       '  "$PROJECT/$LEGACY_BUCKET"'),
    sh("terraform plan"),
    sh("cp legacy.tf.matched legacy.tf\nterraform plan"),
    sh("cp annex.tf.staged annex.tf\ncat annex.tf\nterraform plan"),
    sh("terraform apply -auto-approve"),

    md("## Step 9 · Drift, and which side should win"),
    sh('# The same label edit the runbook makes in the Console\n'
       'gcloud storage buckets update "gs://$RAW_BUCKET" --project "$PROJECT" \\\n'
       '  --update-labels=owner=someone-at-2am'),
    sh("terraform plan"),
    sh("terraform apply -refresh-only -auto-approve"),
    sh("terraform plan"),
    sh('gcloud pubsub topics delete "${TOPIC:?}" --project "${PROJECT:?}" --quiet\n'
       'terraform plan'),
    sh("terraform apply -auto-approve"),

    md("## Step 10 · Surgery on the record"),
    sh("terraform state list\nterraform state rm google_storage_bucket.legacy"),
    sh("terraform plan"),
    sh('rm -f -- "${WORKDIR:?}/legacy.tf"\nterraform plan'),
    sh("cp main.tf.renamed main.tf\nterraform plan"),
    sh("terraform state mv google_storage_bucket.raw google_storage_bucket.landing"),
    sh("terraform plan"),

    md("## Step 11 · Refuse to destroy, then permit it"),
    sh('echo "quarterly totals, and nobody has a copy" > report.csv\n'
       'gcloud storage cp report.csv "gs://$RAW_BUCKET/report.csv" \\\n'
       '  --project "$PROJECT"'),
    sh('cp main.tf.protected main.tf\n'
       'cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh('cp main.tf.renamed main.tf\n'
       'cd "${WORKDIR:?}" && terraform destroy -auto-approve -target=google_storage_bucket.landing'),
    sh("cp main.tf.forced main.tf\nterraform apply -auto-approve"),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),

    md("## After class"),
    sh('gcloud storage rm --recursive --all-versions "gs://${STATE_BUCKET:?}" \\\n'
       '  --project "${PROJECT:?}"\n\n'
       'gcloud storage rm --recursive "gs://${LEGACY_BUCKET:?}" \\\n'
       '  --project "${PROJECT:?}"'),
    sh('gcloud storage rm --recursive "gs://${ANNEX_BUCKET:?}" \\\n'
       '  --project "${PROJECT:?}" 2>/dev/null || echo "annex bucket already removed by terraform destroy"'),
    sh('gcloud storage ls --project "$PROJECT"'),
])
