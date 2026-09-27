#!/usr/bin/env python3
"""
Generate the sample data the Session 5 demonstration measures.

    python3 make-sample.py <OUTPUT_DIR>

Writes three things:

    readings.csv                          200,000 rows, about 12 MB
    readings.parquet                      the same rows, Snappy-compressed
    events/dt=YYYY-MM-DD/part-000.parquet ten daily prefixes, 20,000 rows each

The numbers in the runbook depend on the row counts, so the generator is
seeded. Re-running it produces byte-identical files, and a re-capture therefore
produces the same measurements.

The data is invented industrial telemetry, which is the shape A5's scenario
asks students to design for: a device identifier, a site, a metric name, a
reading, and a timestamp. Nothing here is real and nothing here is sensitive.
"""

import csv
import datetime
import pathlib
import random
import sys

import pyarrow as pa
import pyarrow.parquet as pq

SEED = 6190
ROWS = 200_000
DAYS = 10
ROWS_PER_DAY = 20_000
FIRST_DAY = datetime.date(2026, 9, 8)
EPOCH = datetime.datetime(2026, 9, 8, 0, 0, 0)

PLANTS = ["charlotte", "greensboro", "raleigh", "durham"]
METRICS = ["vibration_mm_s", "temp_c", "pressure_kpa", "rpm"]
COLUMNS = ["reading_id", "device_id", "plant", "metric", "value", "recorded_at"]


def rows(rng, start_id, count, start_time):
    for i in range(count):
        yield (
            start_id + i,
            f"dev-{rng.randint(1, 900):04d}",
            rng.choice(PLANTS),
            rng.choice(METRICS),
            # One decimal place, because a sensor reports a reading rather than
            # a random float. Low cardinality is what dictionary encoding needs,
            # and it is why the Parquet file is small enough to make the point.
            round(rng.uniform(0.0, 240.0), 1),
            (start_time + datetime.timedelta(seconds=i * 3)).isoformat() + "Z",
        )


def table_from(batch):
    cols = list(zip(*batch))
    return pa.table(
        {
            "reading_id": pa.array(cols[0], pa.int64()),
            "device_id": pa.array(cols[1], pa.string()),
            "plant": pa.array(cols[2], pa.string()),
            "metric": pa.array(cols[3], pa.string()),
            "value": pa.array(cols[4], pa.float64()),
            "recorded_at": pa.array(cols[5], pa.string()),
        }
    )


def main(out: pathlib.Path) -> None:
    out.mkdir(parents=True, exist_ok=True)

    rng = random.Random(SEED)
    flat = list(rows(rng, 1, ROWS, EPOCH))

    csv_path = out / "readings.csv"
    with csv_path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(COLUMNS)
        writer.writerows(flat)

    pq.write_table(table_from(flat), out / "readings.parquet", compression="snappy")

    # The partitioned copy. `dt` is a directory name, not a column, so it is
    # deliberately absent from the schema written into each file.
    rng = random.Random(SEED + 1)
    for day in range(DAYS):
        stamp = (FIRST_DAY + datetime.timedelta(days=day)).isoformat()
        start = EPOCH + datetime.timedelta(days=day)
        batch = list(rows(rng, day * ROWS_PER_DAY + 1, ROWS_PER_DAY, start))
        part = out / "events" / f"dt={stamp}"
        part.mkdir(parents=True, exist_ok=True)
        table = table_from(batch).drop_columns(["recorded_at"])
        pq.write_table(table, part / "part-000.parquet", compression="snappy")

    parts = sorted((out / "events").rglob("*.parquet"))
    print(f"  readings.csv        {csv_path.stat().st_size:>12,} bytes")
    print(f"  readings.parquet    {(out / 'readings.parquet').stat().st_size:>12,} bytes")
    print(f"  events/             {sum(p.stat().st_size for p in parts):>12,} bytes"
          f"  in {len(parts)} daily prefixes")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 make-sample.py <OUTPUT_DIR>")
    main(pathlib.Path(sys.argv[1]))
