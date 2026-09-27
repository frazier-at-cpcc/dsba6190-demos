#!/usr/bin/env python3
"""
Write the two Bash notebooks that drive the Session 8 demonstration.

    python3 build-notebook.py

    prep.ipynb   about ten minutes ahead: provision the cluster and both images, verify
    demo.ipynb   the demonstration, steps 1 to 11, teardown included

Both run on the Bash kernel. The dispatcher loop runs as a background job
writing to loop.log, and the loop cells show its last lines, so the
demonstration needs no second terminal. The notebooks carry step headings
and commands only. The walkthrough is in RUNBOOK.md.
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WORKDIR = "~/dsba6190-live-demo-08"


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


LOAD = sh(f'source {WORKDIR}/env.sh && echo "$CLUSTER   $IMAGE_BASE" \\\n'
          '  || echo "NOT STAGED. Run prep.ipynb first. Do not run any other cell."')
LOOP_START = './loop.sh > loop.log 2>&1 &\necho $! > loop.pid; echo "loop started"'
LOOP_SHOW = 'tail -6 loop.log'
LOOP_STOP = 'kill "$(cat loop.pid)" 2>/dev/null; sleep 1; grep -c " 200 " loop.log; grep -c " ERR " loop.log'
FULL = 'import json,urllib.request;print(json.load(urllib.request.urlopen("http://localhost:8080/quote"))["ms"],"ms")'

notebook("prep", [
    md("# Session 8 · Before you start"),
    md("## Provision, about ten minutes ahead"),
    sh("./live-setup.sh YOUR_PROJECT_ID"),
    LOAD,
    md("## Verify"),
    sh("kubectl get nodes"),
    sh('gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT/$REPO" --include-tags'),
])

notebook("demo", [
    md("# Session 8 · Build, deploy, update, break, and move\n\n"
       "Queen City Trip Analytics, a fictional South End, Charlotte company, "
       "ships its fare-quote API to the fleets that call it."),
    LOAD,

    md("## Step 1 · The Dockerfile, and the layer cache"),
    sh("cat app/Dockerfile"),
    sh("docker build --progress=plain -t fare-api:local app 2>&1 | grep -E 'CACHED|DONE|\\[[0-9]/[0-9]\\]' | tail -12"),
    sh('echo "# a one-line change" >> app/main.py\n'
       "docker build --progress=plain -t fare-api:local app 2>&1 | grep -E 'CACHED|DONE|\\[[0-9]/[0-9]\\]' | tail -12"),

    md("## Step 2 · Cloud Build, Artifact Registry, and the scan"),
    sh('rm -rf build-live; cp -R app build-live; echo v1 > build-live/VERSION\n'
       'gcloud builds submit build-live --region "$REGION" --tag "$IMAGE_BASE:v1"'),
    sh('gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT/$REPO" --include-tags'),
    sh('gcloud artifacts docker images describe "$IMAGE_BASE:v2" --show-package-vulnerability \\\n'
       "  --format='yaml(package_vulnerability_summary.vulnerabilities)' | grep -E '^ *[A-Z]+:' "),

    md("## Step 3 · Three replicas and a Service"),
    sh("kubectl apply -f manifests/deployment-v1.yaml -f manifests/service.yaml"),
    sh("kubectl rollout status deployment/fare-api"),
    sh("kubectl get pods -l app=fare-api -o wide"),
    sh('for i in $(seq 1 30); do IP=$(kubectl get service fare-api -o jsonpath="{.status.loadBalancer.ingress[0].ip}"); [ -n "$IP" ] && break; sleep 5; done; echo "external IP: $IP"'),
    sh('IP=$(kubectl get service fare-api -o jsonpath="{.status.loadBalancer.ingress[0].ip}")\n'
       'curl -s "http://$IP/quote?pickup=132&dropoff=236"; echo'),

    md("## Step 4 · Delete a pod"),
    sh('kubectl delete pod "$(kubectl get pods -l app=fare-api -o jsonpath=\'{.items[0].metadata.name}\')" --wait=false\n'
       "sleep 3; kubectl get pods -l app=fare-api"),
    sh("kubectl get pods -l app=fare-api"),

    md("## Step 5 · Scale out and in while the dispatcher keeps asking"),
    sh(LOOP_START),
    sh("kubectl scale deployment fare-api --replicas=6\nkubectl rollout status deployment/fare-api\nkubectl get pods -l app=fare-api"),
    sh("kubectl scale deployment fare-api --replicas=3"),
    sh(LOOP_SHOW),

    md("## Step 6 · Rolling update to v2, then undo"),
    sh("kubectl apply -f manifests/deployment-v2.yaml\nkubectl rollout status deployment/fare-api"),
    sh(LOOP_SHOW),
    sh("kubectl rollout history deployment/fare-api"),
    sh("kubectl rollout undo deployment/fare-api\nkubectl rollout status deployment/fare-api"),
    sh(LOOP_SHOW),

    md("## Step 7 · Probes: none, wrong, right"),
    sh("kubectl apply -f manifests/deployment-noprobe.yaml\nkubectl rollout status deployment/fare-api"),
    sh("grep ERR loop.log | tail -8; grep -c ERR loop.log"),
    sh("kubectl apply -f manifests/deployment-badprobe.yaml\nsleep 30; kubectl get pods -l app=fare-api"),
    sh("kubectl describe pod \"$(kubectl get pods -l app=fare-api -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{\"\\n\"}{end}' | head -1)\" \\\n"
       "  | sed -n '/Events:/,$p' | tail -6"),
    sh("kubectl rollout status deployment/fare-api --timeout=20s"),
    sh("kubectl apply -f manifests/deployment-goodprobe.yaml\nkubectl rollout status deployment/fare-api --timeout=300s"),
    sh(LOOP_STOP),

    md("## Step 8 · Two limits, two failures"),
    sh("kubectl apply -f manifests/deployment-oom.yaml\nsleep 40; kubectl get pods -l app=fare-api-oom"),
    sh("kubectl describe pod -l app=fare-api-oom | grep -A6 'Last State'"),
    sh("kubectl apply -f manifests/deployment-throttled.yaml\nkubectl rollout status deployment/fare-api-throttled"),
    sh(f"for i in 1 2 3; do kubectl exec deploy/fare-api -- python -c '{FULL}'; done"),
    sh(f"for i in 1 2 3; do kubectl exec deploy/fare-api-throttled -- python -c '{FULL}'; done"),
    sh("kubectl get pods -l app=fare-api-throttled\nkubectl delete deployment fare-api-oom fare-api-throttled --wait=false"),

    md("## Step 9 · A disruption budget, then a node drain"),
    sh("NODE=$(kubectl get pods -l app=fare-api -o jsonpath='{.items[0].spec.nodeName}'); echo \"$NODE\"\n"
       "kubectl apply -f manifests/pdb-strict.yaml"),
    sh('kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --pod-selector=app=fare-api --timeout=40s 2>&1 | grep -v "^WARNING" | tail -5'),
    sh("kubectl apply -f manifests/pdb.yaml\nkubectl get pdb fare-api"),
    sh('kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --pod-selector=app=fare-api --timeout=120s 2>&1 | grep -v "^WARNING" | tail -5'),
    sh("kubectl get pods -l app=fare-api -o wide"),
    sh('kubectl uncordon "$NODE"'),

    md("## Step 10 · The same image on Cloud Run"),
    sh('time gcloud run deploy qc-fare-api --region "$REGION" --image "$IMAGE_BASE:v2" --allow-unauthenticated --quiet'),
    sh('URL=$(gcloud run services describe qc-fare-api --region "$REGION" --format="value(status.url)")\n'
       'for i in 1 2 3; do curl -s -w "  %{time_total}s" "$URL/quote?pickup=132&dropoff=236"; echo; done'),

    md("## Step 11 · Teardown, in order"),
    sh("kubectl delete service fare-api --wait=true\ngcloud compute forwarding-rules list"),
    sh("kubectl delete deployment fare-api; kubectl delete pdb fare-api"),
    sh('gcloud container clusters delete "${CLUSTER:?}" --zone "${ZONE:?}" --quiet'),
    sh('gcloud run services delete qc-fare-api --region "${REGION:?}" --quiet\n'
       'gcloud artifacts repositories delete "${REPO:?}" --location "${REGION:?}" --quiet'),
    sh('gcloud container clusters list; gcloud run services list --region "$REGION"; gcloud compute forwarding-rules list'),
])
