# Session 5 step scripts · Build and harden a lake

This directory holds one standalone Bash script for each step of the Session 5 demonstration. The
scripts run the same commands as `demo.ipynb`. Each one changes into the working directory, prints a
header for its step, and ends with a short note on what to notice.

## Running the steps

`live-setup.sh` copies this directory into the working directory. Stage the demonstration first,
then load the environment it writes:

```sh
./live-setup.sh YOUR_PROJECT_ID          # or ./steps/00-setup.sh YOUR_PROJECT_ID
source ~/dsba6190-live-demo-05/env.sh
```

`env.sh` exports `PROJECT`, `SUFFIX` and `WORK` and changes into the working directory. From there,
run one step at a time or open the menu:

```sh
./steps/01-read-plan.sh
./steps/menu.sh
```

The scripts apply and destroy with `-auto-approve`. Read the plan in step 1 before you run step 2,
and run the steps in order.

## Step inventory

| Script | Step | What it does |
|---|---|---|
| `00-setup.sh` | 0 | Stages the baseline: the ungoverned bucket, the Cloud KMS key and the sample data |
| `01-read-plan.sh` | 1 | Stages `lake.tf` and runs `terraform plan` to show the four governance controls |
| `02-apply-governed.sh` | 2 | Applies the governed bucket and describes it beside the ungoverned one |
| `03-create-zones.sh` | 3 | Creates five zone prefixes and uploads `readings.csv` into Raw |
| `04-test-public-refusals.sh` | 4 | Makes the ungoverned bucket public, fetches a file anonymously, shows the `412` and `400` refusals on the lake, and revokes the grant |
| `05-versioning-undo.sh` | 5 | Overwrites and deletes a manifest, and restores it from a prior generation both times |
| `06-compare-formats.sh` | 6 | Uploads Parquet, applies the external tables, and compares `Bytes Processed` |
| `07-apply-lifecycle.sh` | 7 | Adds two lifecycle rules as an in-place update |
| `08-retention-refusal.sh` | 8 | Creates the retention bucket, uploads an incident record, and shows the `403` refusal |
| `09-cmek-crypto-shredding.sh` | 9 | Applies the CMEK bucket, disables the key version, shows the refusals, and re-enables it |
| `10-partition-pruning.sh` | 10 | Uploads ten daily partitions, applies the partitioned table, and compares one day with all ten |
| `11-check-org-policy.sh` | 11 | Checks the project's ancestry and its effective organization policy |
| `12-teardown.sh` | 12 | Shows the retention refusal on destroy, clears the period, destroys again, and schedules the key version for destruction |
| `menu.sh` | all | Runs any step from a numbered menu |
