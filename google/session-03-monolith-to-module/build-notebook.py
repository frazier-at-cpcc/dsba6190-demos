#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 3 demonstration.

    python3 build-notebook.py

    prep.ipynb   stage the working directory, verify the plan
    demo.ipynb   steps 1 to 13, teardown and verification included

Commands only, on the Bash kernel. The walkthrough is in RUNBOOK.md. Every
apply and destroy carries -auto-approve, because a notebook cell cannot
answer the yes prompt. Every destructive command names its target as
${VAR:?}, so an empty variable refuses to run rather than widening the
delete.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-03"


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
    return cells


def md(text):
    return ("markdown", text)


def sh(text):
    return ("code", text)


LOAD = sh(f'source {WORKDIR}/env.sh && cd "${{WORKDIR:?}}" && echo "$PROJECT   suffix $SUFFIX" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')

PREP = [
    md("# Session 3 · Before you start"),
    md("## Stage"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## Verify"),
    sh("terraform plan"),
]

DEMO = [
    md("# Session 3 · Monolith to module\n\n"
       "Queen City Trip Analytics, a fictional South End, Charlotte firm, codifies the "
       "nightly-trips bucket it created by hand in Session 1."),
    LOAD,

    md("## Step 1 · The monolith"),
    sh("cat main.tf"),

    md("## Step 2 · Read the diff before you cause it"),
    sh("terraform plan"),

    md("## Step 3 · Apply, then apply again"),
    sh("terraform apply -auto-approve"),
    sh("terraform apply -auto-approve"),

    md("## Step 4 · Update in place"),
    sh("cp main.tf.nearline main.tf\nterraform plan"),
    sh("terraform apply -auto-approve"),

    md("## Step 5 · Destroy and recreate. Stop."),
    sh("cp main.tf.renamed main.tf\nterraform plan"),
    sh("cp main.tf.nearline main.tf"),

    md("## Step 6 · Terraform finds the drift"),
    sh('# Or make the same edit in the Console\n'
       'gcloud storage buckets update "gs://${BUCKET:?}" --update-labels=owner=someone-at-2am'),
    sh("terraform plan"),

    md("## Step 7 · One module, two environments"),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh("cp main.tf.module main.tf\nterraform init"),
    sh("terraform plan"),
    sh("terraform apply -auto-approve"),

    md("## Step 8 · Validation, and labels a caller cannot override"),
    sh("cp -R stages/05-validate/. .\nterraform init >/dev/null\ncp main.tf.typo main.tf\nterraform plan"),
    sh("cp stages/05-validate/main.tf main.tf\nterraform plan"),
    sh("terraform apply -auto-approve"),
    sh("terraform output dev_labels"),

    md("## Step 9 · Safe deletion: prevent_destroy, then force_destroy"),
    sh("cp -R stages/06-protect/. .\nterraform apply -auto-approve"),
    sh('gcloud storage cp trips-2026-09-02.csv "gs://${PROD_BUCKET:?}/raw/"'),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh("cp modules/data-lake/main.tf.unguarded modules/data-lake/main.tf\n"
       'cd "${WORKDIR:?}" && terraform destroy -auto-approve -target=module.prod_lake'),
    sh('gcloud storage ls "gs://${PROD_BUCKET:?}/raw/"'),

    md("## Step 10 · Environments from one map"),
    sh("cp -R stages/07-foreach/. .\nterraform init >/dev/null\nterraform plan"),
    sh("terraform apply -auto-approve"),
    sh("cp main.tf.test main.tf\nterraform plan"),
    sh("terraform apply -auto-approve"),

    md("## Step 11 · The trips VM as a module"),
    sh("cp -R stages/08-vm/. .\nterraform init >/dev/null\nterraform plan -var machine_type=n2-standard-32"),
    sh("date +%s > vm.start\nterraform apply -auto-approve"),
    sh('gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet'),
    sh('gcloud compute instances describe "${VM:?}" --zone "${ZONE:?}" \\\n'
       "  --format='table(name,machineType.basename(),status,deletionProtection)'"),
    sh("terraform apply -auto-approve -var vm_environment=dev"),
    sh("cp stages/07-foreach/main.tf.test main.tf\nterraform apply -auto-approve"),
    sh('S=$(( $(date +%s) - $(cat vm.start) ))\n'
       'python3 -c "s=$S; print(f\'{s} s, {s/3600:.4f} machine-hours, '
       'e2-micro \\${s/3600*0.008376:.6f}, n2-standard-32 \\${s/3600*1.5539:.4f}\')"'),

    md("## Step 12 · Drift as an exit code, and what makes a run reproducible"),
    sh('terraform plan -detailed-exitcode > /dev/null; echo "exit code $?"'),
    sh('# Or make the same edit in the Console\n'
       'gcloud storage buckets update "gs://${PROD_BUCKET:?}" --update-labels=owner=someone-at-2am'),
    sh('terraform plan -detailed-exitcode | grep -E "owner|Plan:"; echo "exit code ${PIPESTATUS[0]}"'),
    sh("sed -n '1,12p' .terraform.lock.hcl"),
    sh("terraform providers"),

    md("## Step 13 · Teardown, and proof that nothing remains"),
    sh('gcloud storage rm "gs://${PROD_BUCKET:?}/**"'),
    sh('cd "${WORKDIR:?}" && terraform destroy -auto-approve'),
    sh('gcloud storage buckets list --filter="name~${SUFFIX:?}" --format="value(name)"\n'
       'gcloud compute instances list --filter="name~${SUFFIX:?}" --format="value(name)"\n'
       'terraform state list\n'
       'echo "listed above: nothing means nothing remains"'),
]

if __name__ == "__main__":
    notebook("prep", PREP)
    notebook("demo", DEMO)
