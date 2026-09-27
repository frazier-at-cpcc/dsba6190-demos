#!/usr/bin/env python3
"""
Write the Bash notebooks for the Session 5 demonstration from steps/*.sh.

    python3 build-notebook.py

The step scripts were verified in class on 17 September 2026. This converts
each one into notebook cells: the banner echo lines are dropped, the
set -e and exit lines are dropped because either would end the notebook's
shell, and each numbered sub-step becomes its own cell. Commands only; what
to say is in RUNBOOK.md.
"""
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
STEPS = sorted((HERE / "steps").glob("[0-9][0-9]-*.sh"))
TITLES = {}


def cells_from(script: pathlib.Path):
    lines = script.read_text().splitlines()
    title = next((l[2:].strip() for l in lines[1:4] if l.startswith("# ")), script.stem)
    out, cur, skip_if = [], [], False
    for l in lines:
        if l.startswith("#!") or l.startswith("#") and not cur and not out:
            continue
        if re.match(r'^\s*set [+-][euo]+( pipefail)?\s*$', l) or re.match(r'^(set -euo pipefail|PROJECT=|SUFFIX=|WORK=|AUTO_APPROVE=|HERE=)', l):
            continue
        if l.startswith("if [ ! -d") or l.startswith("if [ ! -f"):
            skip_if = True
            continue
        if skip_if:
            if l.strip() == "fi":
                skip_if = False
            continue
        if re.match(r'^\s*exit\b', l):
            continue
        m = re.match(r'^echo -e "\\n\\033\[1;34m>>> (.*?)\\033\[0m"', l)
        if m:
            if any(x.strip() for x in cur):
                out.append("\n".join(cur).strip())
            cur = [f"# {m.group(1)}"]
            continue
        if l.startswith("echo"):
            continue
        cur.append(l)
    if any(x.strip() and not x.startswith("#") for x in cur):
        out.append("\n".join(cur).strip())
    return title, [c for c in out if any(x.strip() and not x.lstrip().startswith("#") for x in c.splitlines())]


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
    print(f"wrote {name}.ipynb: {len(cells)} cells, {sum(c['cell_type'] == 'code' for c in cells)} commands")


LOAD = ("code", 'source ~/dsba6190-live-demo-05/env.sh && echo "lake: dsba6190-lake-$SUFFIX" \\\n'
                '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')

notebook("prep", [("markdown", "# Session 5 · Before class"),
                  ("code", "./live-setup.sh YOUR_PROJECT_ID"), LOAD,
                  ("code", "terraform plan")])

parts = [("markdown", "# Session 5 · Build and harden a lake\n\n"
          "Catawba Precision Components, a fictional Charlotte-area manufacturer, "
          "builds the governed data lake its plant telemetry lands in."), LOAD]
for sc in STEPS:
    if sc.name.startswith("00-"):
        continue
    title, cells = cells_from(sc)
    parts.append(("markdown", f"## {title.split(' · slide')[0].split(' · Slide')[0]}"))
    parts += [("code", c) for c in cells]
notebook("demo", parts)
