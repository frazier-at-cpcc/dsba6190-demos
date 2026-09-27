# Session 2 demonstration · Grant it wrong, then fix it

This demonstration accompanies Session 2, IAM, Networking and Security. Crown Street Markets, a
fictional 40-store Charlotte grocery chain, gives its first analyst access to its first analytics
project. The analyst receives Editor on the project, uses it, and loses it. A private VM then learns
to reach Google's APIs without reaching the internet.

Every command was run end to end on 27 September 2026, and `capture/` holds the real output of each
one. Read `RUNBOOK.md` for the walkthrough.

## Key results

| Step | Result | Capture |
|---|---|---|
| 1 | The analyst sees 0 datasets before any grant | `03` |
| 2 | `roles/editor` carries 12,135 permissions, `dataViewer` 23 and `jobUser` 10 | `04` |
| 3 | Editor took effect after 3 s | `06` |
| 4 | With Editor, the analyst reads card numbers, deletes `members_backup` and lists 4 VMs | `07` to `09` |
| 8 | SSH through IAP with no firewall rule gives up after 21 s | `25` |
| 9, 10 | The probe reports no route to all three hosts before Private Google Access, and 400, 404 and no route after it | `27`, `29` |
| 11 | The raw table was refused after a further 132 s, about five minutes after Editor was removed | `12`, `14` |
| 11 | Uptown leads with 113,812 baskets and $5,180,842, and three actions are refused | `13` to `16` |
| 12 | The service account was still listed seconds after its deletion | `31` |

## Known issues and fixes

- Revoking a role takes minutes, while granting one takes seconds. The recorded run needed about
  five minutes before the analyst lost the raw table. Step 5 therefore applies the fix early, and
  step 11 polls until the raw table is refused.
- `bq add-iam-policy-binding` on a dataset can fail with an allowlisting error. Step 5 grants
  `dataViewer` with BigQuery's SQL `GRANT ... ON SCHEMA` statement instead.
- Impersonation can fail for about a minute after the token-creator grant. `live-setup.sh` waits
  until impersonation succeeds before it finishes.
- A service account deleted before its bindings leaves a `deleted:serviceAccount:` member in the
  project policy. Step 12 removes the binding before the account for this reason.

## Files

| Path | What it is |
|---|---|
| `RUNBOOK.md` | The walkthrough, step by step, with the measured results |
| `sample/make-crown.py` | Generates the seeded store sales and loyalty members |
| `lib.sh` | The `q` and `as_analyst` helpers |
| `live-setup.sh` | Creates both datasets and the analyst, and waits for impersonation. It creates resources and never deletes them |
| `capture.sh`, `capture/` | The recorder and its 34 output files |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
