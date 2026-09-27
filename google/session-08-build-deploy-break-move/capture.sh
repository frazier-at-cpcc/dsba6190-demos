#!/usr/bin/env bash
# Capture the Session 8 live demo: build, deploy, update, break, and move.
#
#   ./capture.sh <PROJECT_ID>
#
# Stages with live-setup.sh into .work/, runs all eleven steps against a real
# GKE cluster and Cloud Run, writes every command's real output to capture/,
# and tears everything down through an exit trap in the order step 11
# teaches: the Service first, so the load balancer is released, then the
# cluster, the Cloud Run service and the repository.
#
# Cost of one run: roughly $1. Three e2-medium nodes for about an hour, one
# load balancer, three image builds inside the Cloud Build free tier, and a
# vulnerability scan on each pushed image.
#
# DO NOT RUN THIS IN CLASS. live-setup.sh is the one to run before class.

set -euo pipefail

PROJECT="${1:?usage: ./capture.sh <PROJECT_ID>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HERE/.work"
OUT="$HERE/capture"
export SUFFIX="$(date +%s | tail -c 6)"
REGION=us-central1; ZONE=us-central1-b
CLUSTER="qc-fare-$SUFFIX"; REPO="qc-fare-$SUFFIX"
mkdir -p "$OUT"
export PATH="$PATH:$(gcloud info --format='value(installation.sdk_root)')/bin"
export KUBECONFIG="$WORKDIR/kubeconfig"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
run  () {  # run <label> <outfile> <command...>
  local label="$1"; local out="$OUT/$2"; shift 2
  { printf '$ %s\n\n' "$label"; "$@" 2>&1 || true; } | tee "$out"
}
loop () {  # loop <seconds> <outfile>: the dispatcher loop, in the background
  (cd "$WORKDIR" && { printf '$ ./loop.sh %s   (second terminal)\n\n' "$1"; ./loop.sh "$1"; } \
     > "$OUT/$2" 2>&1) &
}

cleanup () {
  step "Cleanup"
  kubectl delete service fare-api --ignore-not-found --wait=true >/dev/null 2>&1 || true
  gcloud container clusters delete "${CLUSTER:?}" --project "$PROJECT" --zone "$ZONE" --quiet >/dev/null 2>&1 || true
  gcloud run services delete qc-fare-api --project "$PROJECT" --region "$REGION" --quiet >/dev/null 2>&1 || true
  gcloud artifacts repositories delete "${REPO:?}" --project "$PROJECT" --location "$REGION" --quiet >/dev/null 2>&1 || true
  echo "  Cleanup finished."
}
trap cleanup EXIT

step "Stage with live-setup.sh"
"$HERE/live-setup.sh" "$PROJECT" "$WORKDIR" | tee "$OUT/00-live-setup.txt"
# shellcheck disable=SC1091
source "$WORKDIR/env.sh"

# ------------------------------------------------------------ build
step "Step 1 · The Dockerfile, and the layer cache"
run "cat app/Dockerfile" 01-dockerfile.txt cat app/Dockerfile
run "docker build --no-cache app   (first build)" 02-build-cold.txt \
    bash -c "docker build --no-cache --progress=plain -t fare-api:local app 2>&1 | grep -E '^#[0-9]+ (\[|DONE)' | grep -E '\[[0-9]/[0-9]\]|DONE' | tail -16"
echo "# a one-line change" >> app/main.py
run "docker build app   (after a one-line change to main.py)" 03-build-warm.txt \
    bash -c "docker build --progress=plain -t fare-api:local app 2>&1 | grep -E 'CACHED|\[[0-9]/[0-9]\]|DONE' | tail -16"

step "Step 2 · Cloud Build, Artifact Registry, and the scan"
rm -rf build-live; cp -R app build-live; echo v1 > build-live/VERSION
run "gcloud builds submit build-live --tag \$IMAGE_BASE:v1" 04-cloud-build.txt \
    bash -c "gcloud builds submit build-live --project $PROJECT --region $REGION --tag $IMAGE_BASE:v1 2>&1 | grep -E 'Step|DONE|STATUS|ID|DURATION|SUCCESS|pushed|digest' | tail -14"
run "gcloud artifacts docker images list \$REGION-docker.pkg.dev/\$PROJECT/\$REPO --include-tags" 05-images.txt \
    gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT/$REPO" --include-tags \
      --format="table(package.basename(),tags,createTime.date('%H:%M'))"
run "gcloud artifacts docker images describe \$IMAGE_BASE:v2 --show-package-vulnerability" 06-scan.txt \
    bash -c "for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
               out=\$(gcloud artifacts docker images describe $IMAGE_BASE:v2 --show-package-vulnerability \
                        --format='yaml(package_vulnerability_summary.vulnerabilities)' 2>&1)
               echo \"\$out\" | grep -q -E 'CRITICAL|HIGH|MEDIUM|LOW' && { echo \"\$out\" | grep -E '^ *[A-Z]+:|severity|count' | sort | uniq -c | head -20; exit 0; }
               sleep 20
             done; echo 'scan not finished'"

# ------------------------------------------------------------ deploy
step "Step 3 · Three replicas and a Service"
run "kubectl apply -f manifests/deployment-v1.yaml -f manifests/service.yaml" 07-apply.txt \
    kubectl apply -f manifests/deployment-v1.yaml -f manifests/service.yaml
run "kubectl rollout status deployment/fare-api" 08-rollout-v1.txt \
    kubectl rollout status deployment/fare-api --timeout=180s
run "kubectl get pods -o wide" 09-pods.txt \
    kubectl get pods -l app=fare-api -o custom-columns=POD:.metadata.name,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName,IP:.status.podIP
T=$(date +%s); until IP=$(kubectl get service fare-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) && [ -n "$IP" ]; do sleep 5; done
echo "external IP after $(( $(date +%s) - T )) s" > "$OUT/10-ip-wait.txt"
# The IP arrives before the load balancer forwards; wait until it answers.
T=$(date +%s); until curl -s -m 3 -o /dev/null "http://$IP/healthz"; do sleep 5; [ $(( $(date +%s) - T )) -gt 300 ] && break; done
echo "answering after a further $(( $(date +%s) - T )) s" >> "$OUT/10-ip-wait.txt"
run "curl http://\$IP/quote?pickup=132&dropoff=236" 11-curl.txt \
    bash -c "for i in 1 2 3; do curl -s -m 5 'http://$IP/quote?pickup=132&dropoff=236'; echo; done"

step "Step 4 · Delete a pod"
POD=$(kubectl get pods -l app=fare-api -o jsonpath='{.items[0].metadata.name}')
run "kubectl delete pod $POD" 12-delete-pod.txt kubectl delete pod "$POD" --wait=false
sleep 3
run "kubectl get pods   (three seconds later)" 13-pods-after-delete.txt \
    kubectl get pods -l app=fare-api
kubectl rollout status deployment/fare-api --timeout=120s >/dev/null || true
run "kubectl get pods   (settled)" 14-pods-settled.txt kubectl get pods -l app=fare-api

step "Step 5 · Scale out and in while the dispatcher keeps asking"
loop 70 15-loop-scale.txt
sleep 5
run "kubectl scale deployment fare-api --replicas=6" 16-scale-6.txt kubectl scale deployment fare-api --replicas=6
kubectl rollout status deployment/fare-api --timeout=120s >/dev/null || true
run "kubectl get pods" 17-pods-6.txt kubectl get pods -l app=fare-api
run "kubectl scale deployment fare-api --replicas=3" 18-scale-3.txt kubectl scale deployment fare-api --replicas=3
wait

step "Step 6 · Rolling update to v2, then undo"
loop 90 19-loop-rollout.txt
sleep 5
run "kubectl apply -f manifests/deployment-v2.yaml" 20-apply-v2.txt kubectl apply -f manifests/deployment-v2.yaml
run "kubectl rollout status deployment/fare-api" 21-rollout-v2.txt kubectl rollout status deployment/fare-api --timeout=180s
run "kubectl rollout history deployment/fare-api" 22-history.txt kubectl rollout history deployment/fare-api
run "kubectl rollout undo deployment/fare-api" 23-undo.txt kubectl rollout undo deployment/fare-api
run "kubectl rollout status deployment/fare-api" 24-rollout-undo.txt kubectl rollout status deployment/fare-api --timeout=180s
wait

step "Step 7 · Probes: none, wrong, right"
loop 100 25-loop-noprobe.txt
sleep 5
run "kubectl apply -f manifests/deployment-noprobe.yaml   (25 s model load, no readiness probe)" 26-apply-noprobe.txt \
    kubectl apply -f manifests/deployment-noprobe.yaml
run "kubectl rollout status deployment/fare-api" 27-rollout-noprobe.txt kubectl rollout status deployment/fare-api --timeout=240s
wait
loop 75 28-loop-badprobe.txt
sleep 5
run "kubectl apply -f manifests/deployment-badprobe.yaml   (probe on /readyz, which does not exist)" 29-apply-badprobe.txt \
    kubectl apply -f manifests/deployment-badprobe.yaml
sleep 45
run "kubectl get pods" 30-pods-badprobe.txt kubectl get pods -l app=fare-api
NEWPOD=$(kubectl get pods -l app=fare-api -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}' | head -1)
run "kubectl describe pod $NEWPOD | grep -A8 Events" 31-describe-badprobe.txt \
    bash -c "kubectl describe pod $NEWPOD | sed -n '/Events:/,\$p' | tail -8"
run "kubectl rollout status deployment/fare-api --timeout=20s" 32-rollout-stalled.txt \
    kubectl rollout status deployment/fare-api --timeout=20s
wait
loop 110 33-loop-goodprobe.txt
sleep 5
run "kubectl apply -f manifests/deployment-goodprobe.yaml   (the same load, the probe on /ready)" 34-apply-goodprobe.txt \
    kubectl apply -f manifests/deployment-goodprobe.yaml
run "kubectl rollout status deployment/fare-api" 35-rollout-goodprobe.txt kubectl rollout status deployment/fare-api --timeout=300s
wait

step "Step 8 · Two limits, two failures"
run "kubectl apply -f manifests/deployment-oom.yaml   (holds 256 MiB, limit 64 MiB)" 36-apply-oom.txt \
    kubectl apply -f manifests/deployment-oom.yaml
sleep 50
run "kubectl get pods -l app=fare-api-oom" 37-pods-oom.txt kubectl get pods -l app=fare-api-oom
run "kubectl describe pod -l app=fare-api-oom | grep -A6 'Last State'" 38-describe-oom.txt \
    bash -c "kubectl describe pod -l app=fare-api-oom | grep -A6 'Last State'"
run "kubectl apply -f manifests/deployment-throttled.yaml   (CPU limit 100m)" 39-apply-throttled.txt \
    kubectl apply -f manifests/deployment-throttled.yaml
kubectl rollout status deployment/fare-api-throttled --timeout=180s >/dev/null || true
Q='import json,urllib.request;print(json.load(urllib.request.urlopen("http://localhost:8080/quote"))["ms"],"ms")'
run "kubectl exec deploy/fare-api -- python -c <one quote>   (CPU limit 1)" 40-quote-full-cpu.txt \
    bash -c "for i in 1 2 3; do kubectl exec deploy/fare-api -- python -c '$Q'; done"
run "kubectl exec deploy/fare-api-throttled -- python -c <one quote>   (CPU limit 100m)" 41-quote-throttled.txt \
    bash -c "for i in 1 2 3; do kubectl exec deploy/fare-api-throttled -- python -c '$Q'; done"
run "kubectl get pods   (the throttled pod is Running and Ready)" 42-throttled-healthy.txt \
    kubectl get pods -l app=fare-api-throttled
kubectl delete deployment fare-api-oom fare-api-throttled --wait=false >/dev/null

step "Step 9 · A disruption budget, then a node drain"
NODE=$(kubectl get pods -l app=fare-api -o jsonpath='{.items[0].spec.nodeName}')
run "kubectl apply -f manifests/pdb-strict.yaml   (minAvailable 3)" 43-pdb-strict.txt kubectl apply -f manifests/pdb-strict.yaml
run "kubectl drain $NODE --pod-selector=app=fare-api --timeout=40s" 44-drain-refused.txt \
    bash -c "kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --pod-selector=app=fare-api --timeout=40s 2>&1 | grep -v '^WARNING' | tail -6"
run "kubectl apply -f manifests/pdb.yaml   (minAvailable 2)" 45-pdb.txt kubectl apply -f manifests/pdb.yaml
run "kubectl get pdb fare-api" 46-pdb-status.txt kubectl get pdb fare-api
run "kubectl drain $NODE --pod-selector=app=fare-api --timeout=120s" 47-drain-ok.txt \
    bash -c "kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --pod-selector=app=fare-api --timeout=120s 2>&1 | grep -v '^WARNING' | tail -6"
kubectl rollout status deployment/fare-api --timeout=180s >/dev/null || true
kubectl wait --for=condition=Ready pod -l app=fare-api --timeout=120s >/dev/null 2>&1 || true
run "kubectl get pods -o wide   (the evicted pod rescheduled elsewhere)" 48-pods-after-drain.txt \
    kubectl get pods -l app=fare-api -o custom-columns=POD:.metadata.name,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName
run "kubectl uncordon $NODE" 49-uncordon.txt kubectl uncordon "$NODE"

step "Step 10 · The same image on Cloud Run"
run "time gcloud run deploy qc-fare-api --image \$IMAGE_BASE:v2 --allow-unauthenticated" 50-run-deploy.txt \
    bash -c "S=\$(date +%s); gcloud run deploy qc-fare-api --project $PROJECT --region $REGION --image $IMAGE_BASE:v2 --allow-unauthenticated --quiet 2>&1 | grep -E 'Deploying|Service|URL|Done|traffic' ; echo; echo \"wall clock \$(( \$(date +%s) - S )) s\""
URL=$(gcloud run services describe qc-fare-api --project "$PROJECT" --region "$REGION" --format='value(status.url)')
run "curl \$URL/quote" 51-run-curl.txt \
    bash -c "for i in 1 2 3; do curl -s -m 20 -w '  %{time_total}s' '$URL/quote?pickup=132&dropoff=236'; echo; done"
run "gcloud run services describe qc-fare-api   (scaling)" 52-run-scaling.txt \
    bash -c "gcloud run services describe qc-fare-api --project $PROJECT --region $REGION --format=yaml 2>&1 | grep -E 'autoscaling.knative.dev/(min|max)Scale|containerConcurrency|cpu:|memory:' | sort -u"

step "Step 11 · Teardown, in order"
run "kubectl delete service fare-api   (first, to release the load balancer)" 53-delete-service.txt \
    kubectl delete service fare-api --wait=true
run "gcloud compute forwarding-rules list" 54-forwarding-rules.txt \
    gcloud compute forwarding-rules list --project "$PROJECT"
run "kubectl delete deployment fare-api; kubectl delete pdb fare-api" 55-delete-workload.txt \
    bash -c "kubectl delete deployment fare-api; kubectl delete pdb fare-api"
run "gcloud container clusters delete \$CLUSTER --quiet" 56-delete-cluster.txt \
    bash -c "S=\$(date +%s); gcloud container clusters delete ${CLUSTER:?} --project $PROJECT --zone $ZONE --quiet 2>&1 | tail -2; echo \"wall clock \$(( \$(date +%s) - S )) s\""
run "gcloud run services delete qc-fare-api --quiet" 57-delete-run.txt \
    gcloud run services delete qc-fare-api --project "$PROJECT" --region "$REGION" --quiet
run "gcloud artifacts repositories delete \$REPO --quiet" 58-delete-repo.txt \
    gcloud artifacts repositories delete "${REPO:?}" --project "$PROJECT" --location "$REGION" --quiet
run "verify: clusters, Cloud Run services, forwarding rules, repositories" 59-verify.txt \
    bash -c "gcloud container clusters list --project $PROJECT; gcloud run services list --project $PROJECT --region $REGION; gcloud compute forwarding-rules list --project $PROJECT; gcloud artifacts repositories list --project $PROJECT --location $REGION"

step "Mask identifiers"
ME="$(gcloud config get-value account 2>/dev/null)"
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
for f in "$OUT"/*.txt; do
  sed -i '' -e "s/$ME/instructor@example.edu/g" -e "s/$NUMBER/PROJECT_NUMBER/g" "$f"
done
echo "Captured $(ls "$OUT"/*.txt | wc -l | tr -d ' ') files into $OUT"
