"""
Crown Street Markets · register-events stream.

The fictional 40-store Charlotte grocery chain publishes one message per
completed sale. This pipeline turns them into one-minute sales-by-store
windows in BigQuery, which the store managers' staffing dashboard reads.

    python register_stream.py --variant {baseline,lateness,dedup} \
        --subscription projects/P/subscriptions/S --dlq_topic projects/P/topics/T \
        --table P:dataset.table  <Dataflow pipeline options>

    baseline   event-time windows, no allowed lateness, no deduplication
    lateness   the same, with 60 minutes of allowed lateness and a late re-fire
    dedup      the same as baseline, reading with id_label='sale_id'

Every variant routes a record it cannot parse to the dead-letter topic with
the error attached, rather than retrying it forever.
"""
import argparse
import json
import logging

import apache_beam as beam
from apache_beam import window
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions
from apache_beam.transforms.trigger import AccumulationMode, AfterCount, AfterWatermark


class Parse(beam.DoFn):
    DEAD = "dead"

    def process(self, msg):
        try:
            sale = json.loads(msg.data.decode("utf-8"))
            store = sale["store_id"]
            total = float(sale["total"])
            yield (store, total)
        except Exception as e:  # noqa: BLE001 - every failure goes to the dead-letter path
            yield beam.pvalue.TaggedOutput(
                self.DEAD, beam.io.PubsubMessage(msg.data, {"error": f"{type(e).__name__}: {e}"[:500],
                                                           **(msg.attributes or {})}))


class ToRow(beam.DoFn):
    def process(self, kv, w=beam.DoFn.WindowParam, pane=beam.DoFn.PaneInfoParam):
        store, totals = kv
        yield {"window_start": w.start.to_utc_datetime().isoformat(),
               "store_id": store, "sales": len(totals), "revenue": round(sum(totals), 2),
               "pane": pane.timing.name if hasattr(pane.timing, "name") else str(pane.timing)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", required=True, choices=["baseline", "lateness", "dedup"])
    ap.add_argument("--subscription", required=True)
    ap.add_argument("--dlq_topic", required=True)
    ap.add_argument("--table", required=True)
    args, rest = ap.parse_known_args()
    opts = PipelineOptions(rest)
    opts.view_as(StandardOptions).streaming = True

    read = beam.io.ReadFromPubSub(subscription=args.subscription, with_attributes=True,
                                  timestamp_attribute="event_ts",
                                  id_label="sale_id" if args.variant == "dedup" else None)
    if args.variant == "lateness":
        win = beam.WindowInto(window.FixedWindows(60), allowed_lateness=3600,
                              trigger=AfterWatermark(late=AfterCount(1)),
                              accumulation_mode=AccumulationMode.ACCUMULATING)
    else:
        win = beam.WindowInto(window.FixedWindows(60))

    p = beam.Pipeline(options=opts)
    if True:
        parsed = (p | "Read" >> read
                    | "Parse" >> beam.ParDo(Parse()).with_outputs(Parse.DEAD, main="sales"))
        (parsed.sales
         | "Window" >> win
         | "ByStore" >> beam.GroupByKey()
         | "Row" >> beam.ParDo(ToRow())
         | "Write" >> beam.io.WriteToBigQuery(
             args.table,
             schema="window_start:TIMESTAMP,store_id:STRING,sales:INTEGER,revenue:FLOAT,pane:STRING",
             create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
             write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
             method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS))
        parsed[Parse.DEAD] | "DeadLetter" >> beam.io.WriteToPubSub(args.dlq_topic, with_attributes=True)
    result = p.run()
    # A streaming job never finishes. On Dataflow, submit and return; locally, wait.
    if opts.get_all_options().get("runner") in (None, "DirectRunner"):
        result.wait_until_finish()
    else:
        print(f"submitted {result.job_id()}")


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.WARNING)
    main()
