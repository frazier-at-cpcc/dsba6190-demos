#!/usr/bin/env bash
# Interactive step runner for the Session 5 demo (Suffix: 86612)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  clear
  echo "================================================================="
  echo " DSBA 6190 · Session 5 Demo: Build & Harden a Lake"
  echo " Active Session Suffix: 86612 | Project: YOUR_PROJECT_ID"
  echo "================================================================="
  echo " 0) Step 0  · Baseline Setup (Run First)"
  echo " 1) Step 1  · Read Plan (Governed Bucket)"
  echo " 2) Step 2  · Apply Governed Bucket"
  echo " 3) Step 3  · Create 5 Zones & Upload CSV"
  echo " 4) Step 4  · Test Public Refusals (HTTP 412/400)"
  echo " 5) Step 5  · Versioning Undo & Recovery"
  echo " 6) Step 6  · Compare Formats (CSV vs Parquet)"
  echo " 7) Step 7  · Apply Lifecycle Rules"
  echo " 8) Step 8  · Retention Policy & Refusal"
  echo " 9) Step 9  · CMEK Crypto-Shredding"
  echo "10) Step 10 · Partition Pruning (10x Scan Savings)"
  echo "11) Step 11 · Check Org Policy"
  echo "12) Step 12 · Teardown & Destruction"
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
