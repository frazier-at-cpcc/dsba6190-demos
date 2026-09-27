#!/usr/bin/env bash
# Step 0: Baseline Setup for Session 5 Demo
# Run this BEFORE class to stage the estate with suffix 86612.
#
#   ./steps/00-setup.sh [PROJECT_ID] [WORKDIR] [SUFFIX]
#
set -euo pipefail

PROJECT="${1:-${PROJECT:-YOUR_PROJECT_ID}}"
WORK="${2:-${WORK:-$HOME/dsba6190-live-demo-05}}"
SUFFIX="${3:-${SUFFIX:-86612}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "\033[1;32m=================================================================\033[0m"
echo -e "\033[1;32m>>> Session 5 Live Demo: Step 0 · Baseline Setup\033[0m"
echo -e "\033[1;32m    Project: $PROJECT | Suffix: $SUFFIX | Workdir: $WORK\033[0m"
echo -e "\033[1;32m=================================================================\033[0m"

# Call the idempotent live-setup script
"$HERE/live-setup.sh" "$PROJECT" "$WORK" "$SUFFIX"

echo -e "\n\033[1;34m[Verification]\033[0m Checking terraform plan in $WORK..."
(cd "$WORK" && terraform plan)

echo -e "\n\033[1;32m>>> Step 0 complete. Ready for Step 1 at 1:30.\033[0m"
