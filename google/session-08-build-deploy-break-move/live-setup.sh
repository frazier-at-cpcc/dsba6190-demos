#!/usr/bin/env bash
# Stage the Session 8 live demo: build, deploy, update, break, and move.
#
#   ./live-setup.sh <PROJECT_ID> [WORKDIR]
#
# Provisions what the hour cannot wait for: the Artifact Registry repository,
# the v1 and v2 images of Queen City Trip Analytics' fare-quote API, and a
# three-node GKE Standard cluster with both images already pulled onto every
# node. It deploys nothing the hour deploys. Steps 3 onward create the
# Deployment, the Service, the budget and the Cloud Run service in front of
# the room.
#
# Run it at T minus 45. Cluster creation is the slow part.
# Applies. Never destroys. The teardown it prints is step 11.

set -euo pipefail

PROJECT="${1:?usage: ./live-setup.sh <PROJECT_ID> [WORKDIR]}"
WORK="${2:-$HOME/dsba6190-live-demo-08}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${SUFFIX:-$(date +%s | tail -c 6)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-b}"
CLUSTER="qc-fare-$SUFFIX"
REPO="qc-fare-$SUFFIX"
IMAGE_BASE="$REGION-docker.pkg.dev/$PROJECT/$REPO/fare-api"
export PATH="$PATH:$(gcloud info --format='value(installation.sdk_root)')/bin"
export KUBECONFIG="$WORK/kubeconfig"

step () { printf '\n\033[1;32m>>> %s\033[0m\n' "$1"; }
T0=$(date +%s)

step "APIs"
for api in container.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
           run.googleapis.com containerscanning.googleapis.com; do
  gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
         --format="value(config.name)" | grep -q . \
    || gcloud services enable "$api" --project "$PROJECT" >/dev/null
done

rm -rf "$WORK"; mkdir -p "$WORK"

step "The cluster, started now because it is the slow part"
gcloud container clusters create "$CLUSTER" --project "$PROJECT" --zone "$ZONE" \
  --num-nodes 3 --machine-type e2-medium --disk-size 30 \
  --release-channel regular --workload-pool "$PROJECT.svc.id.goog" \
  --labels course=dsba6190,session=08,company=queen-city-trip-analytics \
  --async --quiet >/dev/null

step "The repository and both images"
gcloud artifacts repositories create "$REPO" --project "$PROJECT" --location "$REGION" \
  --repository-format docker --description "Queen City Trip Analytics fare-quote API" >/dev/null
for v in v1 v2; do
  rm -rf "$WORK/build-$v"; cp -R "$HERE/app" "$WORK/build-$v"; echo "$v" > "$WORK/build-$v/VERSION"
  # A freshly enabled Cloud Build API refuses builds for a few minutes. On
  # 27 September 2026 the first submit failed with PERMISSION_DENIED and the
  # same command succeeded three minutes later.
  for i in 1 2 3 4 5 6; do
    gcloud builds submit "$WORK/build-$v" --project "$PROJECT" --region "$REGION" \
      --tag "$IMAGE_BASE:$v" --quiet >/dev/null 2>&1 && break
    [ "$i" -eq 6 ] && { echo "Cloud Build still refusing after six attempts"; exit 1; }
    sleep 45
  done
done

step "Wait for the cluster"
until [ "$(gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --zone "$ZONE" \
            --format='value(status)' 2>/dev/null)" = "RUNNING" ]; do sleep 15; done
gcloud container clusters get-credentials "$CLUSTER" --project "$PROJECT" --zone "$ZONE" >/dev/null 2>&1

step "Pull both images onto every node, then remove the puller"
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: prepull}
spec:
  selector: {matchLabels: {app: prepull}}
  template:
    metadata: {labels: {app: prepull}}
    spec:
      initContainers:
      - {name: v1, image: "$IMAGE_BASE:v1", command: ["true"]}
      - {name: v2, image: "$IMAGE_BASE:v2", command: ["true"]}
      containers:
      - {name: pause, image: "registry.k8s.io/pause:3.9"}
YAML
kubectl rollout status daemonset/prepull --timeout=300s >/dev/null
kubectl delete daemonset prepull --wait=true >/dev/null

step "The working directory"
cp -R "$HERE/app" "$WORK/app"
mkdir -p "$WORK/manifests"
for f in "$HERE"/manifests/*.yaml; do
  sed "s#IMAGE_BASE#$IMAGE_BASE#g" "$f" > "$WORK/manifests/$(basename "$f")"
done
cp "$HERE/loop.sh" "$WORK/loop.sh"
cat > "$WORK/env.sh" <<ENVEOF
export PROJECT="$PROJECT"
export REGION="$REGION"
export ZONE="$ZONE"
export SUFFIX="$SUFFIX"
export WORK="$WORK"
export CLUSTER="$CLUSTER"
export REPO="$REPO"
export IMAGE_BASE="$IMAGE_BASE"
export KUBECONFIG="$WORK/kubeconfig"
export PATH="\$PATH:$(gcloud info --format='value(installation.sdk_root)')/bin"
cd "$WORK"
ENVEOF
READY=$(( $(date +%s) - T0 ))

cat <<DONE

  Staged for the live demo in $(( READY / 60 )) min $(( READY % 60 )) s. Nothing is deployed.

  Working directory   $WORK
  Name suffix         $SUFFIX
  Cluster             $CLUSTER   ($ZONE, three e2-medium nodes, both images pulled)
  Images              $IMAGE_BASE:v1
                      $IMAGE_BASE:v2

  Load the names into the shell you will teach from:

      source $WORK/env.sh

  NOT created. The hour creates each of these at its own step:
    Deployment fare-api and Service fare-api   step 3
    fare-api-oom, fare-api-throttled           step 8
    PodDisruptionBudget fare-api               step 9
    Cloud Run service qc-fare-api              step 10

  Teardown is step 11, and it is also, in this order:
    kubectl delete service fare-api
    gcloud container clusters delete $CLUSTER --zone $ZONE --project $PROJECT --quiet
    gcloud run services delete qc-fare-api --region $REGION --project $PROJECT --quiet
    gcloud artifacts repositories delete $REPO --location $REGION --project $PROJECT --quiet
DONE
