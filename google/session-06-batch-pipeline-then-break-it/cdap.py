#!/usr/bin/env python3
"""
Drive a Cloud Data Fusion instance through its CDAP REST API.

    python3 cdap.py <OP> [options]

A Data Fusion pipeline is a JSON document and the Studio canvas is a renderer
for it. Everything the Studio does over the wire is a call to the same v3 REST
API this script uses, which is what lets the Studio's clicks be captured as
text. The walkthrough uses the UI, because the canvas, the Wrangler grid and
the lineage view are visual. The capture uses this script, because a
screenshot cannot be diffed and a log line can.

Operations:

    artifacts   list the plugin artifacts the instance actually carries
    deploy      PUT a pipeline JSON as an application
    start       start the pipeline's workflow, print the run id
    wait        poll one run to a terminal state, print state and duration
    runs        print the run records for an application
    logs        print a run's logs
    stages      print per-stage input and output record counts for a run
    lineage     print field-level lineage for a dataset
    delete      delete an application
"""

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

WORKFLOW_NAME = "DataPipelineWorkflow"
WORKFLOW = f"workflows/{WORKFLOW_NAME}"
TERMINAL = {"COMPLETED", "FAILED", "KILLED", "STOPPED", "REJECTED"}


def token() -> str:
    return subprocess.run(["gcloud", "auth", "print-access-token"],
                          capture_output=True, text=True, check=True).stdout.strip()


def call(endpoint, path, method="GET", body=None, raw=False, tok=None, root=False):
    base = "v3" if root else "v3/namespaces/default"
    url = f"{endpoint.rstrip('/')}/{base}/{path.lstrip('/')}"
    data = body.encode() if isinstance(body, str) else body
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {tok or token()}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            text = r.read().decode()
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        print(f"HTTP {e.code}\n{text}")
        sys.exit(0 if raw else 1)
    if raw:
        return text
    return json.loads(text) if text.strip() else {}


def op_artifacts(a):
    arts = call(a.endpoint, "artifacts?scope=SYSTEM")
    wanted = {"google-cloud", "wrangler-transform", "core-plugins", "cdap-data-pipeline"}
    for art in sorted(arts, key=lambda x: x["name"]):
        if art["name"] in wanted:
            print(f"{art['name']:<24} {art['version']:<12} {art['scope']}")


def op_deploy(a):
    body = open(a.file).read()
    call(a.endpoint, f"apps/{a.app}", method="PUT", body=body, raw=True)
    app = call(a.endpoint, f"apps/{a.app}")
    stages = app.get("configuration")
    n = len(json.loads(stages)["stages"]) if stages else 0
    conns = len(json.loads(stages)["connections"]) if stages else 0
    print(f"Deployed  {a.app}")
    print(f"  artifact   {app['artifact']['name']} {app['artifact']['version']}")
    print(f"  stages     {n}")
    print(f"  edges      {conns}")


def op_start(a):
    before = {r["runid"] for r in call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/runs")}
    call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/start", method="POST", body="{}", raw=True)
    for _ in range(60):
        runs = call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/runs")
        new = [r for r in runs if r["runid"] not in before]
        if new:
            print(new[0]["runid"])
            return
        time.sleep(2)
    sys.exit("no new run appeared")


def op_wait(a):
    tok = token()
    t0 = time.time()
    last = None
    while time.time() - t0 < a.timeout:
        r = call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/runs/{a.run}", tok=tok)
        state = r.get("status")
        if state != last:
            # Flushed, because this is the one command a reader watches
            # while it works and the recorder pipes its output to a file.
            print(f"  {int(time.time() - t0):>5}s  {state}", flush=True)
            last = state
        if state in TERMINAL:
            secs = (r.get("end", 0) - r.get("starting", 0)) or int(time.time() - t0)
            print(f"\nrun      {a.run}")
            print(f"status   {state}")
            print(f"duration {secs}s")
            sys.exit(0 if state == "COMPLETED" else 0)
        time.sleep(15)
        tok = token()
    sys.exit("timed out")


def op_runs(a):
    for r in call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/runs"):
        dur = (r.get("end", 0) - r.get("starting", 0)) if r.get("end") else 0
        print(f"{r['runid']}  {r['status']:<10} {dur:>4}s")


def op_logs(a):
    text = call(a.endpoint, f"apps/{a.app}/{WORKFLOW}/runs/{a.run}/logs?start=0&max={a.max}",
                raw=True)
    keep = []
    for line in text.splitlines():
        if a.grep and a.grep.lower() not in line.lower():
            continue
        keep.append(line)
    print("\n".join(keep[-a.tail:] if a.tail else keep))


def op_stages(a):
    """Per-stage record counts. This is the number the Studio prints on each
    node after a run, read from the same metrics the canvas reads.

    The metrics service is not under /v3/namespaces/<ns>. It is at /v3/metrics
    and takes namespace, app and run as tags rather than as a path."""
    tok = token()
    # The run tag alone matches nothing. A run is identified by the program
    # that produced it as well as by its id, so the workflow tag has to be
    # there too, and a query naming a metric the stage never emitted returns an
    # empty series rather than a partial one.
    tags = f"tag=namespace:default&tag=app:{a.app}"
    if a.run:
        tags += f"&tag=workflow:{WORKFLOW_NAME}&tag=run:{a.run}"
    metrics = "&".join(f"metric=user.{a.stage}.records.{k}" for k in ("in", "out"))
    r = call(a.endpoint, f"metrics/query?{tags}&{metrics}&aggregate=true",
             method="POST", body="{}", tok=tok, root=True)
    series = r.get("series", [])
    if not series:
        print(f"{a.stage:<22} no records metric was emitted for this stage")
        return
    for s in series:
        name = s["metricName"].replace(f"user.{a.stage}.records.", "")
        val = s["data"][0]["value"] if s.get("data") else 0
        print(f"{a.stage:<22} records {name:<8} {val}")


def op_lineage(a):
    end = int(time.time()) + 60
    start = end - a.window
    r = call(a.endpoint,
             f"datasets/{a.dataset}/lineage/fields?start={start}&end={end}&includeCurrent=true")
    fields = r if isinstance(r, list) else r.get("fields", [])
    print(f"dataset  {a.dataset}")
    print(f"fields   {len(fields)}")
    for f in fields:
        print(f"  {f}")


def op_field_ops(a):
    end = int(time.time()) + 60
    start = end - a.window
    r = call(a.endpoint,
             f"datasets/{a.dataset}/lineage/fields/{a.field}/operations"
             f"?start={start}&end={end}&direction=incoming")
    print(json.dumps(r, indent=2)[:a.max])


def op_delete(a):
    call(a.endpoint, f"apps/{a.app}", method="DELETE", raw=True)
    print(f"Deleted  {a.app}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("op")
    p.add_argument("--endpoint", required=True)
    p.add_argument("--app")
    p.add_argument("--file")
    p.add_argument("--run")
    p.add_argument("--stage")
    p.add_argument("--dataset")
    p.add_argument("--field")
    p.add_argument("--grep")
    p.add_argument("--tail", type=int, default=0)
    p.add_argument("--max", type=int, default=4000)
    p.add_argument("--window", type=int, default=7200)
    p.add_argument("--timeout", type=int, default=1800)
    a = p.parse_args()
    fn = globals().get(f"op_{a.op.replace('-', '_')}")
    if not fn:
        sys.exit(f"unknown op {a.op}")
    fn(a)


if __name__ == "__main__":
    main()
