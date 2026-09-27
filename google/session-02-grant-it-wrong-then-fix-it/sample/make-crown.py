#!/usr/bin/env python3
"""
Write Crown Street Markets' two tables as CSV.

    python3 make-crown.py OUTDIR

Crown Street Markets is a fictional 40-store Charlotte grocery chain.
store_sales.csv is curated: one row per store per day, no customer data.
loyalty_members.csv is raw: one row per loyalty member, with the email and
card number an analyst never needs. Every value is synthetic and seeded.
"""
import csv, random, sys, pathlib, datetime as dt
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
rng = random.Random(20260827)
AREAS = ["Uptown", "South End", "NoDa", "Plaza Midwood", "Dilworth", "SouthPark", "Ballantyne",
         "University City", "Steele Creek", "Matthews", "Mint Hill", "Huntersville", "Cornelius",
         "Pineville", "Elizabeth", "Myers Park", "Cotswold", "Montford", "Camp North End", "Mountain Island"]
stores = [(f"CLT-{i:03d}", AREAS[(i - 1) % len(AREAS)]) for i in range(1, 41)]
with open(out / "store_sales.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["store_id", "neighborhood", "sale_date", "baskets", "revenue_usd"])
    for d in range(28):
        day = dt.date(2026, 8, 1) + dt.timedelta(days=d)
        for sid, area in stores:
            b = int(rng.gauss(1800, 350) * (1.25 if day.weekday() >= 5 else 1))
            w.writerow([sid, area, day.isoformat(), b, round(b * rng.uniform(38, 52), 2)])
first = ["Ava", "Jamal", "Sofia", "Wei", "Mateo", "Priya", "Liam", "Aaliyah", "Noah", "Hana"]
last = ["Brooks", "Nguyen", "Patel", "Garcia", "Johnson", "Kim", "Okafor", "Rivera", "Smith", "Chen"]
with open(out / "loyalty_members.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["member_id", "full_name", "email", "card_number", "home_store"])
    for i in range(5000):
        fn, ln = rng.choice(first), rng.choice(last)
        w.writerow([f"M-{i:06d}", f"{fn} {ln}", f"{fn.lower()}.{ln.lower()}{i}@example.com",
                    "6011" + "".join(str(rng.randrange(10)) for _ in range(12)), rng.choice(stores)[0]])
print(f"wrote {len(stores) * 28} store-days and 5,000 members to {out}")
