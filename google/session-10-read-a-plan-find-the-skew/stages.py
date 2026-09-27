#!/usr/bin/env python3
"""
Summarise task durations per stage from a Spark event log, the way the Spark
UI's stage page does.

    python3 stages.py <event-log-file>
    python3 stages.py --largest <event-log-file>

Prints one row per stage: tasks, min, 25th, median, 75th, max seconds, and
the max-to-median ratio. A ratio far above 1 on a stage with many tasks is
the signature of skew.

With --largest it prints, for each stage that reads a shuffle, the single
task that read the most bytes: its bytes, its records and its seconds. That
is the partition adaptive query execution compares against
spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes.

With --app-time it prints how long the Spark application itself ran, from
its start event to its end event. The rest of a batch's wall clock is
provisioning, submission and shutdown.

With --final-plan it prints the plan adaptive query execution actually ran
for the job's write, which the plan printed before execution cannot show.
"""
import json
import statistics
import sys
from collections import defaultdict

largest = sys.argv[1] == "--largest"
path = sys.argv[-1]

if sys.argv[1] == "--app-time":
    t = {}
    for line in open(path):
        e = json.loads(line)
        if e.get("Event") in ("SparkListenerApplicationStart", "SparkListenerApplicationEnd"):
            t[e["Event"]] = e["Timestamp"]
    print(f"application ran {(t['SparkListenerApplicationEnd'] - t['SparkListenerApplicationStart']) / 1000:.1f} s")
    sys.exit(0)

if sys.argv[1] == "--final-plan":
    for line in open(path):
        e = json.loads(line)
        p = e.get("physicalPlanDescription", "")
        if e.get("Event", "").endswith("AdaptiveExecutionUpdate") and "isFinalPlan=true" in p:
            tree = p.split("== Physical Plan ==")[1].split("\n\n")[0]
            for row in tree.strip("\n").splitlines():
                if "== Initial Plan ==" in row:
                    break
                print(row.split(", [plan_id")[0].split(" Batched:")[0][:110])
            break
    sys.exit(0)
stage_names, durations, shuffle = {}, defaultdict(list), defaultdict(int)
top = defaultdict(lambda: (0, 0, 0.0))
for line in open(path):
    e = json.loads(line)
    if e.get("Event") == "SparkListenerStageSubmitted":
        s = e["Stage Info"]
        stage_names[s["Stage ID"]] = s["Stage Name"].split(" at ")[0]
    elif e.get("Event") == "SparkListenerTaskEnd":
        info = e["Task Info"]
        durations[e["Stage ID"]].append((info["Finish Time"] - info["Launch Time"]) / 1000)
        m = e.get("Task Metrics") or {}
        r = m.get("Shuffle Read Metrics") or {}
        b = r.get("Remote Bytes Read", 0) + r.get("Local Bytes Read", 0)
        shuffle[e["Stage ID"]] += b
        if b > top[e["Stage ID"]][0]:
            top[e["Stage ID"]] = (b, r.get("Total Records Read", 0),
                                  (info["Finish Time"] - info["Launch Time"]) / 1000)

if largest:
    print(f"{'stage':>5}  {'largest task reads':>18}  {'records':>11}  {'seconds':>7}")
    for sid, (b, n, s) in sorted(top.items()):
        if b > 1e6:
            print(f"{sid:>5}  {b / 1e6:>15.1f} MB  {n:>11,}  {s:>7.1f}")
    sys.exit(0)

print(f"{'stage':>5} {'tasks':>6} {'min':>6} {'p25':>6} {'median':>7} {'p75':>6} {'max':>7} {'max/med':>8}  shuffle read")
for sid in sorted(durations):
    d = sorted(durations[sid])
    q = statistics.quantiles(d, n=4) if len(d) > 1 else [d[0]] * 3
    med = statistics.median(d)
    ratio = d[-1] / med if med else 0
    print(f"{sid:>5} {len(d):>6} {d[0]:>6.1f} {q[0]:>6.1f} {med:>7.1f} {q[2]:>6.1f} {d[-1]:>7.1f} {ratio:>8.1f}  "
          f"{shuffle[sid] / 1e6:>8.1f} MB")
