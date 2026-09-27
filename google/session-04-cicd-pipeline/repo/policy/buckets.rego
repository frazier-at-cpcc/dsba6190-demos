# Pipeline policy for the DSBA 6190 infrastructure pipeline.
#
# These rules run against the JSON form of a Terraform plan, so they judge
# what will happen rather than what someone wrote. Each rule names the
# resource address and the reason, because a gate that can explain itself
# is the point of pipeline policy. Organization Policy is the other layer:
# it denies the API call even when the pipeline is bypassed, but it cannot
# say which line of HCL caused the refusal.

package main

import rego.v1

public_members := {"allUsers", "allAuthenticatedUsers"}

approved_locations := {"US-EAST1", "US-CENTRAL1", "US"}

required_labels := {"owner", "env"}

changed(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

members(rc) := {rc.change.after.member} if {
	rc.type == "google_storage_bucket_iam_member"
}

members(rc) := {m | some m in rc.change.after.members} if {
	rc.type == "google_storage_bucket_iam_binding"
}

# Rule 1. No public buckets.
deny contains msg if {
	some rc in input.resource_changes
	rc.type in {"google_storage_bucket_iam_member", "google_storage_bucket_iam_binding"}
	changed(rc)
	some m in members(rc)
	m in public_members
	msg := sprintf("%s grants %s. Public access to a bucket is not permitted.", [rc.address, m])
}

# Rule 2. Mandatory labels.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "google_storage_bucket"
	changed(rc)
	present := {k | some k, _ in rc.change.after.labels}
	missing := required_labels - present
	count(missing) > 0
	msg := sprintf("%s is missing required labels %v.", [rc.address, missing])
}

# Rule 3. Approved locations only.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "google_storage_bucket"
	changed(rc)
	loc := upper(rc.change.after.location)
	not loc in approved_locations
	msg := sprintf("%s is in %s. Approved locations are %v.", [rc.address, rc.change.after.location, approved_locations])
}

# Rule 4. No destroy-and-recreate of a bucket without an explicit override.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "google_storage_bucket"
	"delete" in rc.change.actions
	"create" in rc.change.actions
	not rc.change.after.labels["allow-replace"] == "true"
	msg := sprintf("%s would be destroyed and recreated. Add the label allow-replace = \"true\" to say that this is intended.", [rc.address])
}
