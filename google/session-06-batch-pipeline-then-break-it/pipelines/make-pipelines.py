#!/usr/bin/env python3
"""
Emit the three Session 6 pipeline definitions as CDAP pipeline JSON.

    python3 make-pipelines.py <OUTDIR> <PROJECT> <BUCKET> <DATASET> \
        --gcp-version X --wrangler-version Y --core-version Z

A Data Fusion pipeline is a JSON document. The Studio canvas is a renderer for
it, and the REST API accepts the same document the Studio exports. Writing the
three variants here rather than clicking them into existence is what lets the
demonstration be captured as text and replayed against a fresh instance.

The three variants differ by exactly one design decision each, which is the
point of building them as a sequence:

    01-baseline    GCS -> Wrangler -> BigQuery. Loads whatever arrives.
    02-quarantine  the same, plus an error collector and a GCS error sink.
    03-idempotent  the same as 02, with BOTH sinks made safe to run twice: the
                   BigQuery sink truncates rather than appends, and the error
                   sink writes a run-scoped prefix rather than a fixed one.
                   Fixing only the first is not enough, and the rehearsal on
                   10 September proved it.
    04-drift       the same as 03, with one directive removed, so the source's
                   amount column reaches a FLOAT64 column as a string. This one
                   is built to fail, and the failure is the teaching.
"""

import argparse
import json
from pathlib import Path

# The schema Wrangler emits and the BigQuery sink receives. Written once and
# referenced by every stage that needs it, because CDAP carries the schema as a
# string on each stage rather than deriving it.
OUT_FIELDS = [
    {"name": "txn_id", "type": ["string", "null"]},
    {"name": "store_id", "type": ["string", "null"]},
    {"name": "txn_ts", "type": [{"type": "long", "logicalType": "timestamp-micros"}, "null"]},
    {"name": "sku", "type": ["string", "null"]},
    {"name": "qty", "type": ["int", "null"]},
    {"name": "amount", "type": ["double", "null"]},
]
OUT_SCHEMA = json.dumps({"type": "record", "name": "pos", "fields": OUT_FIELDS})

TEXT_SCHEMA = json.dumps({
    "type": "record", "name": "textfile",
    "fields": [{"name": "offset", "type": "long"}, {"name": "body", "type": "string"}],
})

ERROR_SCHEMA = json.dumps({
    "type": "record", "name": "quarantined",
    "fields": [
        {"name": "errCode", "type": ["int", "null"]},
        {"name": "errMsg", "type": ["string", "null"]},
        {"name": "errStage", "type": ["string", "null"]},
        {"name": "invalidRecord", "type": ["string", "null"]},
    ],
})

# The Wrangler recipe, as the directive list Wrangler itself stores. Every line
# below is a directive a student would produce by clicking a column header in
# the Wrangler UI, and the recipe is what those clicks accumulate into. Naming
# the recipe as code is step 2 of the demonstration.
RECIPE_LINES = [
    "parse-as-csv :body ',' true",
    "drop :body",
    "drop :offset",
    "rename body_1 txn_id",
    "rename body_2 store_id",
    "rename body_3 txn_ts",
    "rename body_4 sku",
    "rename body_5 qty",
    "rename body_6 amount",
    "set-type :qty integer",
    "set-type :amount double",
    "parse-as-datetime :txn_ts 'yyyy-MM-dd HH:mm:ss'",
    "datetime-to-timestamp :txn_ts",
]
RECIPE = "\n".join(RECIPE_LINES)


def stage(name, plugin_name, plugin_type, artifact, version, props, schema=None):
    s = {
        "name": name,
        "plugin": {
            "name": plugin_name,
            "type": plugin_type,
            "label": name,
            "artifact": {"name": artifact, "version": version, "scope": "SYSTEM"},
            "properties": props,
        },
    }
    if schema:
        s["outputSchema"] = schema
    return s


def gcs_source(a, bucket, obj, project):
    return stage(
        "PointOfSaleRaw", "GCSFile", "batchsource", "google-cloud", a["gcp"],
        {
            "project": project,
            "format": "text",
            "path": f"gs://{bucket}/raw/pos/{obj}",
            "referenceName": "pos_raw",
            "serviceAccountType": "filePath",
            "serviceFilePath": "auto-detect",
            "schema": TEXT_SCHEMA,
            "copyHeader": "false",
            "enableQuotedValues": "false",
            "recursive": "false",
            "filenameOnly": "false",
        },
        TEXT_SCHEMA,
    )


def wrangler(a, on_error, recipe=None, schema=None):
    return stage(
        "Wrangler", "Wrangler", "transform", "wrangler-transform", a["wrangler"],
        {
            "field": "*",
            "precondition": "false",
            "directives": recipe or RECIPE,
            "on-error": on_error,
            "schema": schema or OUT_SCHEMA,
            "workspaceId": "pos",
        },
        schema or OUT_SCHEMA,
    )


def bq_sink(a, project, dataset, table, operation, truncate, partition_field=None):
    props = {
        "project": project,
        "dataset": dataset,
        "table": table,
        "referenceName": f"bq_{table}",
        "serviceAccountType": "filePath",
        "serviceFilePath": "auto-detect",
        "operation": operation,
        "truncateTable": truncate,
        "allowSchemaRelaxation": "false",
        "location": "us-central1",
        "createPartitionedTable": "false",
        "schema": OUT_SCHEMA,
    }
    if partition_field:
        props["createPartitionedTable"] = "true"
        props["partitionByField"] = partition_field
        props["partitionFilterRequired"] = "false"
    return stage("SalesValidated", "BigQueryTable", "batchsink", "google-cloud", a["gcp"],
                 props, OUT_SCHEMA)


def error_collector(a):
    return stage(
        "QuarantineCollector", "ErrorCollector", "errortransform", "core-plugins", a["core"],
        {"messageField": "errMsg", "codeField": "errCode", "stageField": "errStage"},
        ERROR_SCHEMA,
    )


def gcs_error_sink(a, project, bucket, run_scoped=False):
    # A Hadoop output committer refuses to write into a directory that already
    # exists, so a fixed path makes the sink fail on the second run rather than
    # append to it. The rehearsal on 10 September hit exactly that:
    #
    #   Stage 'QuarantineSink' encountered :
    #   org.apache.hadoop.mapred.FileAlreadyExistsException:
    #   Output directory gs://.../quarantine/pos already exists
    #
    # The fix is the deterministic partition target the lecture already teaches.
    # `logicalStartTime` is a CDAP macro evaluated per run, so each run writes
    # its own dated prefix and re-running overwrites nothing.
    path = f"gs://{bucket}/quarantine/pos"
    if run_scoped:
        path += "/dt=${logicalStartTime(yyyy-MM-dd-HHmmss)}"
    return stage(
        "QuarantineSink", "GCS", "batchsink", "google-cloud", a["gcp"],
        {
            "project": project,
            "referenceName": "pos_quarantine",
            "path": path,
            "format": "json",
            "serviceAccountType": "filePath",
            "serviceFilePath": "auto-detect",
            "location": "us-central1",
            "schema": ERROR_SCHEMA,
        },
        ERROR_SCHEMA,
    )


def envelope(name, description, stages, connections, version):
    return {
        "name": name,
        "description": description,
        "artifact": {"name": "cdap-data-pipeline", "version": version, "scope": "SYSTEM"},
        "config": {
            "resources": {"memoryMB": 2048, "virtualCores": 1},
            "driverResources": {"memoryMB": 2048, "virtualCores": 1},
            "connections": connections,
            "comments": [],
            "postActions": [],
            "properties": {},
            "processTimingEnabled": True,
            "stageLoggingEnabled": True,
            "engine": "spark",
            "numOfRecordsPreview": 100,
            "maxConcurrentRuns": 1,
            "stages": stages,
        },
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("outdir")
    p.add_argument("project")
    p.add_argument("bucket")
    p.add_argument("dataset")
    p.add_argument("--gcp-version", default="0.24.0")
    p.add_argument("--wrangler-version", default="4.11.0")
    p.add_argument("--core-version", default="2.13.0")
    p.add_argument("--pipeline-version", default="6.11.1")
    p.add_argument("--source-object", default="pos-2026-09-24.csv")
    args = p.parse_args()

    a = {"gcp": args.gcp_version, "wrangler": args.wrangler_version, "core": args.core_version}
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    pv = args.pipeline_version

    # 01 · baseline. Three stages, two edges, and no opinion about bad data.
    # on-error 'skip-error' is Wrangler's default and is the behaviour step 6
    # exists to make visible.
    base = envelope(
        "pos-01-baseline",
        "Point of sale, raw to validated. GCS source, Wrangler transform, BigQuery sink.",
        [
            gcs_source(a, args.bucket, args.source_object, args.project),
            wrangler(a, "skip-error"),
            bq_sink(a, args.project, args.dataset, "sales_validated", "insert", "false"),
        ],
        [
            {"from": "PointOfSaleRaw", "to": "Wrangler"},
            {"from": "Wrangler", "to": "SalesValidated"},
        ],
        pv,
    )
    (out / "01-baseline.json").write_text(json.dumps(base, indent=2) + "\n")

    # 02 · quarantine. The same three stages, plus the branch. Wrangler stops
    # discarding bad rows and starts emitting them on its error port.
    quar = envelope(
        "pos-02-quarantine",
        "The same pipeline, with an error collector and a quarantine sink on Wrangler's error port.",
        [
            gcs_source(a, args.bucket, args.source_object, args.project),
            wrangler(a, "send-to-error-port"),
            bq_sink(a, args.project, args.dataset, "sales_validated", "insert", "false"),
            error_collector(a),
            gcs_error_sink(a, args.project, args.bucket),
        ],
        [
            {"from": "PointOfSaleRaw", "to": "Wrangler"},
            {"from": "Wrangler", "to": "SalesValidated"},
            {"from": "Wrangler", "to": "QuarantineCollector"},
            {"from": "QuarantineCollector", "to": "QuarantineSink"},
        ],
        pv,
    )
    (out / "02-quarantine.json").write_text(json.dumps(quar, indent=2) + "\n")

    # 03 · idempotent. One property changes. The sink truncates the table
    # before it writes, so the run replaces the day rather than adding to it.
    idem = envelope(
        "pos-03-idempotent",
        "The quarantine pipeline, with both sinks made safe to run twice.",
        [
            gcs_source(a, args.bucket, args.source_object, args.project),
            wrangler(a, "send-to-error-port"),
            bq_sink(a, args.project, args.dataset, "sales_validated", "insert", "true"),
            error_collector(a),
            gcs_error_sink(a, args.project, args.bucket, run_scoped=True),
        ],
        [
            {"from": "PointOfSaleRaw", "to": "Wrangler"},
            {"from": "Wrangler", "to": "SalesValidated"},
            {"from": "Wrangler", "to": "QuarantineCollector"},
            {"from": "QuarantineCollector", "to": "QuarantineSink"},
        ],
        pv,
    )
    (out / "03-idempotent.json").write_text(json.dumps(idem, indent=2) + "\n")

    # 04 · schema drift. One directive is gone. The `set-type :amount double`
    # line that made the amount column numeric is removed, exactly as it would
    # be if an upstream team changed the column and nobody updated the recipe.
    # The BigQuery sink is writing into a table that already exists with the
    # column as FLOAT64, and `allowSchemaRelaxation` is false, so the sink is
    # asked to put a string where a number belongs.
    drift_recipe = "\n".join(l for l in RECIPE_LINES if l != "set-type :amount double")
    drift_fields = [dict(f) for f in OUT_FIELDS]
    for f in drift_fields:
        if f["name"] == "amount":
            f["type"] = ["string", "null"]
    drift_schema = json.dumps({"type": "record", "name": "pos", "fields": drift_fields})

    drift = envelope(
        "pos-04-drift",
        "The same pipeline after an upstream change, writing a string into a numeric column.",
        [
            gcs_source(a, args.bucket, args.source_object, args.project),
            wrangler(a, "send-to-error-port", recipe=drift_recipe, schema=drift_schema),
            stage("SalesValidated", "BigQueryTable", "batchsink", "google-cloud", a["gcp"], {
                "project": args.project,
                "dataset": args.dataset,
                "table": "sales_validated",
                "referenceName": "bq_sales_validated",
                "serviceAccountType": "filePath",
                "serviceFilePath": "auto-detect",
                "operation": "insert",
                "truncateTable": "true",
                "allowSchemaRelaxation": "false",
                "location": "us-central1",
                "createPartitionedTable": "false",
                "schema": drift_schema,
            }, drift_schema),
            error_collector(a),
            gcs_error_sink(a, args.project, args.bucket, run_scoped=True),
        ],
        [
            {"from": "PointOfSaleRaw", "to": "Wrangler"},
            {"from": "Wrangler", "to": "SalesValidated"},
            {"from": "Wrangler", "to": "QuarantineCollector"},
            {"from": "QuarantineCollector", "to": "QuarantineSink"},
        ],
        pv,
    )
    (out / "04-drift.json").write_text(json.dumps(drift, indent=2) + "\n")

    for f in sorted(out.glob("*.json")):
        print(f"  {f.name}  {f.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
