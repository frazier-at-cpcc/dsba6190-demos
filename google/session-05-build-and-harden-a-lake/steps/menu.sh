#!/usr/bin/env bash
# Interactive step runner for Session 5 Live Demo (Suffix: 86612)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  clear
  echo "================================================================="
  echo " DSBA 6190 · Session 5 Live Demo: Build & Harden a Lake"
  echo " Active Session Suffix: 86612 | Project: YOUR_PROJECT_ID"
  echo "================================================================="
  echo " 0) Step 0  · Baseline Setup (Pre-class)"
  echo " 1) Step 1  · Read Plan (Governed Bucket) [Slide 26 · 4m]"
  echo " 2) Step 2  · Apply Governed Bucket [Slide 26 · 5m]"
  echo " 3) Step 3  · Create 5 Zones & Upload CSV [Slide 12 · 4m]"
  echo " 4) Step 4  · Test Public Refusals (HTTP 412/400) [Slide 25 · 5m]"
  echo " 5) Step 5  · Versioning Undo & Recovery [Slide 24 · 6m]"
  echo " 6) Step 6  · Compare Formats (CSV vs Parquet) [Slides 18/20 · 7m]"
  echo " 7) Step 7  · Apply Lifecycle Rules [Slide 11 · 4m]"
  echo " 8) Step 8  · Retention Policy & Refusal [Slides 14/24 · 5m]"
  echo " 9) Step 9  · CMEK Crypto-Shredding [Slide 23 · 7m]"
  echo "10) Step 10 · Partition Pruning (10x Scan Savings) [Slide 15 · 6m]"
  echo "11) Step 11 · Check Org Policy [Slide 25/40 · 3m]"
  echo "12) Step 12 · Teardown & Destruction [Slide 24 · 4m]"
  echo " q) Quit"
  echo "================================================================="
  read -rp "Select step [0-12, q]: " choice

  case "$choice" in
    0) "$HERE/00-setup.sh" ;;
    1) "$HERE/01-read-plan.sh" ;;
    2) "$HERE/02-apply-governed.sh" ;;
    3) "$HERE/03-create-zones.sh" ;;
    4) "$HERE/04-test-public-refusals.sh" ;;
    5) "$HERE/05-versioning-undo.sh" ;;
    6) "$HERE/06-compare-formats.sh" ;;
    7) "$HERE/07-apply-lifecycle.sh" ;;
    8) "$HERE/08-retention-refusal.sh" ;;
    9) "$HERE/09-cmek-crypto-shredding.sh" ;;
    10) "$HERE/10-partition-pruning.sh" ;;
    11) "$HERE/11-check-org-policy.sh" ;;
    12) "$HERE/12-teardown.sh" ;;
    q|Q) echo "Exiting."; exit 0 ;;
    *) echo "Invalid choice: $choice" ;;
  esac

  echo ""
  read -rp "Press [Enter] to return to menu..." _
done
