# Session 5 Live Demo · Step Scripts (VS Code Runner)

This directory contains standalone, executable bash scripts for every step of the **Session 5 Live Demo: Build and Harden a Lake**.

The active session suffix is **`86612`** targeting project **`YOUR_PROJECT_ID`**.

## Visual Studio Code Usage

You can open this folder directly in Visual Studio Code:
```sh
code "./session-05-build-and-harden-a-lake"
```
Or open the active working directory:
```sh
code ~/dsba6190-live-demo-05
```

### Running Steps
From the VS Code integrated terminal (`Ctrl+\`` or `Cmd+\``):
- Run individual step scripts directly:
  ```sh
  ./steps/01-read-plan.sh
  ./steps/02-apply-governed.sh
  ```
- Or launch the interactive menu:
  ```sh
  ./steps/menu.sh
  ```
- Or run via VS Code Tasks (`Terminal -> Run Task...` or `Cmd+Shift+P` -> `Tasks: Run Task`).

---

## Step Inventory

| Script | Step | Description | Deck Slide | Duration |
|---|---|---|---|---|
| [`00-setup.sh`](./00-setup.sh) | Step 0 | Stages baseline estate (`dsba6190-staging-86612`), KMS key, sample data | — | Pre-class |
| [`01-read-plan.sh`](./01-read-plan.sh) | Step 1 | Stages `lake.tf` and runs `terraform plan` to inspect 4 governance controls | Slide 26 | 4 min |
| [`02-apply-governed.sh`](./02-apply-governed.sh) | Step 2 | Applies governed bucket; describes `lake-86612` and `staging-86612` side by side | Slide 26 | 5 min |
| [`03-create-zones.sh`](./03-create-zones.sh) | Step 3 | Creates 5 zone prefixes (`raw`, `validated`, `curated`, `archive`, `quarantine`) and uploads `readings.csv` | Slide 12 | 4 min |
| [`04-test-public-refusals.sh`](./04-test-public-refusals.sh) | Step 4 | Makes staging public, curl test, tests HTTP 412 (PAP) and HTTP 400 (UBLA) refusals on lake, revokes public grant | Slide 25 | 5 min |
| [`05-versioning-undo.sh`](./05-versioning-undo.sh) | Step 5 | Manifest v1 upload, 0-row overwrite, rollback via `#generation`, delete, and recovery | Slide 24 | 6 min |
| [`06-compare-formats.sh`](./06-compare-formats.sh) | Step 6 | Uploads Parquet, applies BigQuery tables, runs queries, and inspects `Bytes Processed` | Slides 18, 20 | 7 min |
| [`07-apply-lifecycle.sh`](./07-apply-lifecycle.sh) | Step 7 | Adds lifecycle rules (Nearline at 30d, Archive at 365d), runs in-place plan/apply | Slide 11 | 4 min |
| [`08-retention-refusal.sh`](./08-retention-refusal.sh) | Step 8 | Provisions vault bucket with retention policy, uploads `_incident.csv`, verifies HTTP 403 refusal | Slides 14, 24 | 5 min |
| [`09-cmek-crypto-shredding.sh`](./09-cmek-crypto-shredding.sh) | Step 9 | CMEK bucket apply, upload sensitive file, disable KMS key version (crypto-shredding), re-enable | Slide 23 | 7 min |
| [`10-partition-pruning.sh`](./10-partition-pruning.sh) | Step 10 | Uploads 10 daily partitions, applies Hive-partitioned table, demonstrates 10x byte savings | Slide 15 | 6 min |
| [`11-check-org-policy.sh`](./11-check-org-policy.sh) | Step 11 | Ancestry check, effective org policy inspection, demonstrates why org policy cannot be overridden | Slide 25, 40 | 3 min |
| [`12-teardown.sh`](./12-teardown.sh) | Step 12 | Teardown teaching step: retention refusal on destroy, clear retention period, clean destroy | Slide 24 | 4 min |
