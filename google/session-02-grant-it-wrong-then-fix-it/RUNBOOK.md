# Session 2 walkthrough · Grant it wrong, then fix it

This walkthrough gives one analyst the wrong access, measures what that access allows, and replaces
it with two narrow roles. It then builds a private network and a VM that reaches Google's APIs
without reaching the internet. The demonstration uses two BigQuery datasets, one analyst service
account, one custom-mode VPC, and one `e2-micro` VM in `us-east1-b`. Every command below was run end
to end on 27 September 2026, and `capture/` holds the full output of each one. You can read the
walkthrough and the captures without running anything.

> **Cost.** Running this demonstration creates billable resources in your own project, on your own
> billing account. The recorded run cost under $0.05: an `e2-micro` VM for about ten minutes and a
> few megabytes of BigQuery queries. IAM, firewall rules and Private Google Access carry no charge.
> Delete what you create, in the order step 12 shows.

`capture.sh` stages, runs and deletes everything in one pass. To follow the steps yourself, prefer
the notebooks. `live-setup.sh` creates resources and never deletes them.

---

## The scenario · Crown Street Markets

**Crown Street Markets** is a fictional 40-store Charlotte grocery chain that returns in Sessions 11
and 12. It gives its first analyst access to its first analytics project. The project holds two
datasets. `crown_curated_NNNNN.store_sales` holds one row per store per day and no customer data.
`crown_raw_NNNNN.loyalty_members` holds 5,000 loyalty members, each with a name, an email and a card
number. The analyst needs revenue by neighborhood and nothing else.

**The analyst is a service account.** In a company, access goes to a group of analysts rather than
to one person. Groups live in Cloud Identity or Google Workspace under an organization. The
demonstration project sits under no organization, so it has no groups. A service account named
`cs-analyst-NNNNN`, displayed as "Crown Street analyst (stands in for the analysts group)", is the
nearest principal you can act as. Every command prefixed `as_analyst` runs through service account
impersonation with the analyst's permissions and nothing more.

---

## Before you start

```sh
./live-setup.sh YOUR_PROJECT_ID          # or run prep.ipynb
source ~/dsba6190-live-demo-02/env.sh
bq ls | grep crown_                            # two datasets
```

You need a project with billing enabled, the `gcloud` and `bq` command-line tools, `jq`, and Python
3. Your account must be able to change the project's IAM policy and create service accounts. The
Owner role allows both.

The script enables four APIs, writes the seeded sample, loads both tables, copies `loyalty_members`
to `members_backup`, creates the analyst's service account, and grants your own account
`roles/iam.serviceAccountTokenCreator` on it. It then waits until impersonation works. It grants the
analyst nothing. Staging took **126 seconds** in the recorded run, and about 100 of those seconds
were the wait for impersonation.

Run the steps from `demo.ipynb` on the Bash kernel. In VS Code, choose **Select Kernel**, **Jupyter
Kernel**, **Bash**. Every command is a cell, and the two wait loops print how long they waited.

The Console is optional. At step 3 you can make the Editor grant on **IAM and Admin**, **IAM**,
**Grant access** instead of the command line. The role picker there lists Basic roles above every
predefined role.

---

## The sequence

| # | Step |
|---|---|
| 1 | Two datasets, and what the analyst sees |
| 2 | How big each role is |
| 3 | Grant Editor on the project |
| 4 | What Editor lets the analyst do |
| 5 | Fix it: two roles, each at its own level |
| 6 | Read the policy at both levels |
| 7 | The account nobody granted, and the key nobody holds |
| 8 | A private network, a VM, and no way in |
| 9 | One firewall rule, and still no way out |
| 10 | Private Google Access |
| 11 | After: the fix, verified |
| 12 | Teardown, bindings before the account |

### Step 1 · Two datasets, and the analyst sees neither

As yourself, `bq ls` shows `crown_curated_26041` and `crown_raw_26041`. A three-row query on the raw
table returns names, emails and card numbers. As the analyst, the same listing returns **0
datasets**. **What to notice.** IAM denies everything that no binding allows. Every grant from here
on is a decision.

### Step 2 · How big each role is

`roles/editor` carries **12,135** permissions. `roles/bigquery.dataViewer` carries **23** and
`roles/bigquery.jobUser` carries **10**. **What to notice.** The two small roles cover everything
the analyst needs. Editor is the role the Console offers first.

### Step 3 · Grant it wrong

```sh
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/editor --condition=None --quiet
```

The grant took effect in **3 seconds**. The binding in the recorded run lists four members. The
first is `deleted:serviceAccount:cs-analyst-25186@...`, an analyst from an earlier run whose binding
outlived it. **What to notice.** The grant took three seconds to take effect. Step 11 compares a
revocation against that figure.

### Step 4 · What Editor lets the analyst do

As the analyst, three commands succeed. The analyst reads card numbers. It deletes `members_backup`
with no prompt, and your own listing confirms that the table is gone. It lists every VM in the
project, **four** in the recorded run, which belonged to other demonstrations in the same project.
**What to notice.** Nobody broke in. A valid grant that is far too broad caused all three results.

### Step 5 · Fix it

```sh
gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/editor --condition=None --quiet
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ANALYST" \
  --role roles/bigquery.jobUser --condition=None --quiet
q "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$PROJECT.$CURATED\` TO 'serviceAccount:$ANALYST'"
```

The analyst receives `jobUser` on the project, because every query is a job and jobs run in a
project. It receives `dataViewer` on the curated dataset only. The raw dataset receives nothing.
**What to notice.** The analyst can still read card numbers for several minutes after this step.
Steps 6 to 10 fill that time on purpose.

### Step 6 · Read the policy at both levels

The project policy, filtered to the analyst, shows `roles/bigquery.jobUser` only. The curated
dataset's access list shows the analyst as `READER`, beside `projectWriters`, `projectOwners` and
`projectReaders`. **What to notice.** `projectWriters` explains how step 4's delete worked. Every
project Editor is a writer on every dataset. An audit reads every level. This JSON is the artifact
that Terraform manages in Session 3.

### Step 7 · The account nobody granted, and the key nobody holds

The default Compute Engine service account holds `roles/editor`. Nobody typed that grant. Enabling
the Compute Engine API made it, because the project has no organization policy to block it. In the
recorded run it also holds `roles/datafusion.serviceAgent` from other work in the project. The
analyst's key list shows one key, `SYSTEM_MANAGED`. **What to notice.** Impersonation issued
short-lived tokens throughout the demonstration. No key file exists to leak.

### Step 8 · A private network, a VM, and no way in

```sh
gcloud compute networks create "$NET" --subnet-mode custom
gcloud compute networks subnets create "$SUBNET" --network "$NET" --region "$REGION" --range 10.20.0.0/24
gcloud compute instances create "$VM" --zone "$ZONE" --machine-type e2-micro --subnet "$SUBNET" --no-address ...
gcloud compute firewall-rules list --filter="network:$NET"
time timeout 60 gcloud compute ssh "$VM" --zone "$ZONE" --tunnel-through-iap ...
```

The network is in custom mode, with one subnet at `10.20.0.0/24` and Private Google Access off. The
VM sits at `10.20.0.2` with no external IP, and the network has no firewall rules. SSH through
Identity-Aware Proxy hung and **gave up after 21 seconds**. **What to notice.** The implied
deny-ingress rule drops the packet silently. The failure is a timeout, not an error.

### Step 9 · One firewall rule, and still no way out

```sh
gcloud compute firewall-rules create "$FW" --network "$NET" --direction INGRESS --allow tcp:22 \
  --source-ranges 35.235.240.0/20
```

`35.235.240.0/20` is the IAP range, so SSH arrives only through Google's authenticated tunnel. SSH
now works and runs `probe.sh`. `storage.googleapis.com`, `bigquery.googleapis.com` and `example.com`
all report **no route (timed out)**. **What to notice.** Egress is allowed, but a VM with no
external IP and no Cloud NAT reaches nothing outside its network. That includes Google's own APIs.

### Step 10 · Private Google Access

```sh
gcloud compute networks subnets update "$SUBNET" --region "$REGION" --enable-private-ip-google-access
```

The same probe returns Cloud Storage **400**, BigQuery **404**, and `example.com` still **no
route**. **What to notice.** A 400 and a 404 are replies from the API front end to a bare URL, and
the reply is the point. The setting is on the subnet. Nothing on the VM changed.

### Step 11 · After: the fix, verified

This step measures propagation, and propagation is the reason the fix goes in at step 5. A grant
took effect in 3 seconds at step 3. A revocation takes minutes. Google documents that access changes
typically take about two minutes and sometimes seven minutes or longer. Earlier runs of this
demonstration landed across that range, from 84 seconds to more than seven minutes.

In the run on 27 September, the raw table became unreadable about five minutes after Editor was
removed. The step 11 wait added **132 s** after the network steps. The BigQuery job timestamps give
the total: the step 5 `GRANT` job started at 12:23:12, and the refused card-number query at step 11
ran at 12:28:28.

Run the wait cell first. It polls the raw table as the analyst every ten seconds and prints how long
it waited. Then run the four checks as the analyst.

- Revenue by neighborhood from the curated dataset succeeds. Uptown leads with **113,812** baskets
  and **$5,180,842** across 28 days.
- The card-number query is refused with `Access Denied ... User does not have permission to query
  table`.
- `bq rm` on `store_sales` is refused with `Permission bigquery.tables.delete denied`.
- `gcloud compute instances list` is refused with `Required 'compute.instances.list' permission`.

**What to notice.** The person waiting for new access sees it at once. Nobody sees access being
removed, so a revocation needs a test, not an assumption.

### Step 12 · Teardown, bindings before the account

```sh
gcloud compute instances delete "${VM:?}" --zone "${ZONE:?}" --quiet
gcloud compute firewall-rules delete "${FW:?}" --quiet
gcloud compute networks subnets delete "${SUBNET:?}" --region "${REGION:?}" --quiet
gcloud compute networks delete "${NET:?}" --quiet
gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:${ANALYST:?}" \
  --role roles/bigquery.jobUser --condition=None --quiet
gcloud iam service-accounts delete "${ANALYST:?}" --quiet
bq --project_id="$PROJECT" rm -r -f -d "${CURATED:?}"
bq --project_id="$PROJECT" rm -r -f -d "${RAW:?}"
```

The VM goes first, because a subnet that holds an instance cannot be deleted. The binding goes
before the account, or the policy keeps a `deleted:` member like the one at step 3. Every name is
written `${NAME:?}`, so an empty variable refuses to run instead of deleting the wrong thing. The
verification found no network and no `crown_` datasets. The service account listing still returned
the analyst seconds after the delete returned. Run the listing again a minute later to confirm that
the account is gone.

---

## Known issues and fixes

| Symptom | Fix |
|---|---|
| `as_analyst` fails with a token-creation error | A new token-creator grant takes a minute or two to reach IAM. `live-setup.sh` waits for it. Wait a minute and rerun the cell |
| `bq add-iam-policy-binding` on the curated dataset fails with an allowlisting error | Use the SQL `GRANT ... ON SCHEMA` statement that step 5 runs |
| Step 3's wait loop runs longer than a minute | Grants usually land in seconds. Let the loop finish |
| The Editor binding at step 3 lists a `deleted:serviceAccount:` member | An earlier run deleted its analyst before removing the binding. The member is harmless. Step 12 removes bindings before the account for this reason |
| Step 7 shows no `roles/editor` for the default Compute Engine service account | Your project sits under an organization whose policy blocks the automatic grant. That result is the protection working |
| SSH at step 9 still times out | The rule takes a few seconds to apply. Wait fifteen seconds and rerun. Check that `--source-ranges` is `35.235.240.0/20` |
| The probe at step 10 still reports no route | Private Google Access takes a few seconds to apply. Wait twenty seconds and rerun the probe |
| Step 11 still reads card numbers after Editor was removed | Revocation propagates in minutes. Let the wait loop run. If it passes seven minutes, delete the VM from step 12, rerun the three refusals, and then finish the teardown |
| The analyst's service account is still listed after step 12 | Deletion takes a short time to appear. Run the listing again after a minute |

---

## Files

| Path | What it is |
|---|---|
| `sample/make-crown.py` | Generates the seeded `store_sales.csv` and `loyalty_members.csv` |
| `lib.sh` | Shell helpers. `q` runs a query and prints bytes billed, and `as_analyst` impersonates the analyst |
| `live-setup.sh`, `capture.sh`, `capture/` | Staging, the recorder, and 34 files of real output |
| `prep.ipynb`, `demo.ipynb`, `build-notebook.py` | The Bash notebooks, commands only, and the script that writes them |
