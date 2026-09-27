# Session 2 live demo · grant it wrong, then fix it

The hour-long IAM and networking demonstration for Session 2, IAM, Networking and Security, taught
Thursday 27 August 2026. Crown Street Markets, a fictional 40-store Charlotte grocery chain, gives
its first analyst access to its first analytics project. The analyst receives Editor on the
project, uses it, and loses it. A private VM then learns to reach Google's APIs without reaching the
internet.

Rehearsed and captured on 27 September 2026 against project `YOUR_PROJECT_ID`. It replaces the
thirteen Console screenshots in `../session-02-iam-console-walkthrough/`, which were the delivered
version. One of those screenshots, the Basic-roles-first role picker, stays in the deck as slide 31.

## What the rehearsal changed

- **Revocation took minutes, not seconds.** Removing Editor left the raw table readable for 84
  seconds in one rehearsal, more than seven minutes in another, and about five minutes in the final
  capture. One capture reached its verification step with Editor still in effect. The fix therefore
  goes in at step 5 and is verified at step 11, with a wait loop that polls until the raw table is
  refused. The deck teaches the delay on slide 39.
- **`bq add-iam-policy-binding` on the dataset failed with an allowlisting error.** Step 5 grants
  `dataViewer` with BigQuery's SQL `GRANT ... ON SCHEMA` instead, which also shows the level in the
  statement.
- **Impersonation failed for about a minute after the token-creator grant.** `live-setup.sh` now
  waits until `gcloud auth print-access-token --impersonate-service-account` succeeds.
- **A deleted analyst's binding survived its deletion.** Step 3's output lists
  `deleted:serviceAccount:cs-analyst-25186`, left by an earlier rehearsal. Step 12 removes the
  binding before the account, and the deck uses the leftover as evidence.
- **The analyst is a service account.** The project has no organization and therefore no groups.
  The runbook and the scenario slide say so.

## The numbers the deck argues from

| Step | Figure | Capture |
|---|---|---|
| 1 | The analyst sees 0 datasets before any grant | `03` |
| 2 | `roles/editor` 12,135 permissions; `dataViewer` 23; `jobUser` 10 | `04` |
| 3 | Editor in effect after 3 s | `06` |
| 4 | Editor reads card numbers, deletes `members_backup`, lists 4 VMs | `07` to `09` |
| 8 | SSH through IAP with no firewall rule gives up after 21 s | `25` |
| 9, 10 | Probe: no route to all three before; 400, 404 and no route after Private Google Access | `27`, `29` |
| 11 | Raw table refused after a further 132 s; about five minutes after Editor was removed | `12`, `14` |
| 11 | Uptown 113,812 baskets and $5,180,842; three refusals | `13` to `16` |
| 12 | Service account still listed seconds after deletion | `31` |

## Layout

| Path | What it is |
|---|---|
| `sample/make-crown.py` | Seeded generator for the two tables |
| `lib.sh` | `q` and `as_analyst` helpers |
| `live-setup.sh` | Creates both datasets and the analyst, waits for impersonation. Applies; never destroys |
| `capture.sh`, `capture/` | The recorder and 34 files of real output |
| `RUNBOOK.md`, `Session-02-Live-Demo-Runbook.pdf` | The instructor document |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | Bash notebooks, commands only |
