#!/usr/bin/env python3
"""
Write one night of Queen City Trip Analytics trip records as CSV.

    python3 make-trips.py OUT.csv [ROWS]

Queen City Trip Analytics is fictional. The file stands in for the export a
fleet customer drops each night: one row per completed trip, across twelve
Charlotte neighborhoods. A fixed seed makes every total reproducible.
"""
import csv, random, sys, datetime as dt

ZONES = [("Uptown", 0.22, 14.0), ("South End", 0.16, 12.5), ("NoDa", 0.08, 13.0),
         ("Plaza Midwood", 0.07, 12.0), ("Dilworth", 0.06, 11.5), ("SouthPark", 0.08, 16.0),
         ("Ballantyne", 0.07, 19.5), ("University City", 0.07, 17.0), ("Airport", 0.09, 27.0),
         ("Elizabeth", 0.04, 11.0), ("Myers Park", 0.03, 13.5), ("Camp North End", 0.03, 12.0)]
out = sys.argv[1]
rows = int(sys.argv[2]) if len(sys.argv) > 2 else 2_000_000
rng = random.Random(20260820)
names, weights, base = zip(*[(z, w, b) for z, w, b in ZONES])
day = dt.datetime(2026, 8, 19)
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["trip_id", "pickup_ts", "pickup_zone", "dropoff_zone", "miles", "fare_usd", "vehicle_id"])
    for i in range(rows):
        z = rng.choices(range(len(names)), weights)[0]
        d = rng.choices(range(len(names)), weights)[0]
        ts = day + dt.timedelta(seconds=rng.randrange(86400))
        miles = round(max(0.3, rng.gammavariate(2.0, 1.6 if names[z] != "Airport" else 4.5)), 2)
        fare = round(base[z] * 0.35 + miles * 1.85 + rng.random() * 2, 2)
        w.writerow([f"QC{i:08d}", ts.strftime("%Y-%m-%d %H:%M:%S"), names[z], names[d], miles, fare,
                    f"V{rng.randrange(1, 900):04d}"])
print(f"wrote {rows:,} trips to {out}")
