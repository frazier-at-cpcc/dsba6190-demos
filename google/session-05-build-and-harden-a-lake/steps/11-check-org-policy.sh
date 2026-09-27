#!/usr/bin/env bash
# Step 11 · The guardrail above the project · slide 25 · 3 minutes · Capture step
#
# Inspects project ancestry and effective organization policies.
# Explains why an unmanaged project has no organization above it and why
# organization policies are the enterprise guardrail project owners cannot override.
set -euo pipefail

PROJECT="${PROJECT:-YOUR_PROJECT_ID}"
WORK="${WORK:-$HOME/dsba6190-live-demo-05}"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Step 11 · The guardrail above the project (Capture Step)\033[0m"
echo -e "\033[1;32m    Slide 25 / 40 · 3 minutes · Project: $PROJECT\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

if [ ! -d "$WORK" ]; then
  echo "Error: Working directory $WORK does not exist. Run 00-setup.sh first."
  exit 1
fi

cd "$WORK"

echo -e "\n\033[1;34m$ gcloud projects get-ancestors $PROJECT\033[0m"
gcloud projects get-ancestors "$PROJECT"

echo -e "\n\033[1;34m$ gcloud organizations list\033[0m"
gcloud organizations list || true

echo -e "\n\033[1;34m$ gcloud org-policies list --project=$PROJECT\033[0m"
gcloud org-policies list --project="$PROJECT" || true

echo -e "\n\033[1;34m$ gcloud org-policies describe constraints/storage.publicAccessPrevention --project=$PROJECT --effective\033[0m"
gcloud org-policies describe constraints/storage.publicAccessPrevention \
  --project="$PROJECT" --effective || true

echo -e "\n\033[1;34m>>> Attempting to set project-level organization policy (_pap.yaml)...\033[0m"
cat > _pap.yaml <<YAML
name: projects/$PROJECT/policies/storage.publicAccessPrevention
spec:
  rules:
  - enforce: true
YAML

set +e
gcloud org-policies set-policy _pap.yaml --project="$PROJECT" 2>&1
set -e

echo -e "\n\033[1;33m[Teaching note]\033[0m This project has no parent organization or folder node."
echo "An organization-level Public Access Prevention policy overrides bucket settings and cannot be overridden by project owners."
echo -e "\n\033[1;32m>>> Step 11 complete.\033[0m"
