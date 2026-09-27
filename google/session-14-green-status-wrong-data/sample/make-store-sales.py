#!/usr/bin/env python3
"""
Generate Crown Street Markets' nightly store-sales files for Session 14.

    python3 make-store-sales.py <OUTDIR> [LAST_NIGHT]

Crown Street Markets is a fictional 40-store Charlotte grocery chain. Every
night a load job copies the previous day's register baskets into BigQuery, and
the replenishment dashboard reads the result the next morning.

LAST_NIGHT is the sale date of the most recent load, as YYYY-MM-DD. It defaults
to yesterday on this machine's clock, so the freshness check is true on the day
the demonstration runs. The values are seeded; only the dates move.

Writes:

  raw/dt=YYYY-MM-DD/sales.csv   sixty good nights, the oldest first
  incoming/one-store.csv        last night, but only the Uptown store's feed
  incoming/renamed-column.csv   last night, with basket_value renamed basket_total
  incoming/north-nulls.csv      last night, with basket_value empty in the North region
  load_runs.csv                 thirty nights of load outcomes, for the error budget

The three incoming files each carry one defect and would each load without an
error. That is the point of the session.
"""
import csv
import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 141119
DAYS = 60
AREAS = ["Uptown", "South End", "NoDa", "Plaza Midwood", "Dilworth", "SouthPark", "Ballantyne",
         "University City", "Steele Creek", "Matthews", "Mint Hill", "Huntersville", "Cornelius",
         "Pineville", "Elizabeth", "Myers Park", "Cotswold", "Montford", "Camp North End", "Mountain Island"]
REGION = {"Uptown": "Center City", "South End": "Center City", "NoDa": "Center City",
          "Plaza Midwood": "Center City", "Dilworth": "Center City", "Elizabeth": "Center City",
          "Camp North End": "Center City", "SouthPark": "South", "Ballantyne": "South",
          "Steele Creek": "South", "Pineville": "South", "Myers Park": "South", "Cotswold": "South",
          "Montford": "South", "University City": "North", "Huntersville": "North",
          "Cornelius": "North", "Mountain Island": "North", "Matthews": "East", "Mint Hill": "East"}
STORES = [(f"CLT-{i:03d}", AREAS[(i - 1) % len(AREAS)]) for i in range(1, 41)]
PAYMENTS = [("card", 0.71), ("app", 0.14), ("cash", 0.09), ("ebt", 0.06)]
HEADER = ["sale_date", "store_id", "region", "neighborhood", "register_id", "basket_id",
          "items", "basket_value", "payment_type"]


def pick(rng, pairs):
    r, acc = rng.random(), 0.0
    for v, p in pairs:
        acc += p
        if r < acc:
            return v
    return pairs[-1][0]


def day_rows(rng, day, size):
    rows = []
    for sid, area in STORES:
        n = max(40, int(rng.gauss(300, 18) * size[sid]))
        for b in range(n):
            items = max(1, min(60, int(rng.lognormvariate(2.3, 0.6))))
            value = round(items * rng.uniform(3.1, 4.9), 2)
            rows.append([day.isoformat(), sid, REGION[area], area, f"{sid}-R{rng.randrange(1, 9):02d}",
                         f"{sid}-{day:%Y%m%d}-{b:05d}", items, f"{value:.2f}", pick(rng, PAYMENTS)])
    return rows


def write(path, rows, header=HEADER):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def main(out: Path, last: date):
    rng = random.Random(SEED)
    size = {sid: rng.uniform(0.8, 1.2) for sid, _ in STORES}
    size["CLT-001"] = 1.2                     # the Uptown flagship
    first = last - timedelta(days=DAYS - 1)
    total = 0
    for d in range(DAYS):
        day = first + timedelta(days=d)
        rows = day_rows(rng, day, size)
        write(out / "raw" / f"dt={day.isoformat()}" / "sales.csv", rows)
        total += len(rows)
    # `rows` now holds last night. Each incoming file is last night with one defect.
    one = [r for r in rows if r[1] == "CLT-001"]
    write(out / "incoming" / "one-store.csv", one)
    write(out / "incoming" / "renamed-column.csv", rows,
          header=[("basket_total" if h == "basket_value" else h) for h in HEADER])
    north = [r[:7] + ([""] if r[2] == "North" else [r[7]]) + r[8:] for r in rows]
    write(out / "incoming" / "north-nulls.csv", north)
    north_rows = sum(r[2] == "North" for r in rows)

    # Thirty nights of load outcomes. The job must finish by 06:00 Eastern, when
    # the replenishment dashboard refreshes. Every run reports DONE.
    runs = []
    late = {6: 102, 19: 195}                   # nights the job finished after 06:00
    wrong = {24: (18, "13:20")}                # night 24 loaded a partial feed on time
    for n in range(30):
        night = last - timedelta(days=29 - n)
        start = datetime.combine(night + timedelta(days=1), datetime.min.time()) + timedelta(hours=2)
        if n in late:
            finish = start + timedelta(hours=4, minutes=late[n])
        else:
            finish = start + timedelta(minutes=rng.randint(38, 81))
        share = 1.0
        fixed = ""
        if n in wrong:
            share = wrong[n][0] / 600          # 3 per cent of a normal night
            fixed = f"{(night + timedelta(days=1)).isoformat()} {wrong[n][1]}:00"
        runs.append([night.isoformat(), "DONE", finish.strftime("%Y-%m-%d %H:%M:%S"),
                     int(12000 * share * rng.uniform(0.97, 1.03)), fixed])
    write(out / "load_runs.csv", runs,
          header=["sale_date", "state", "finished_at", "rows_loaded", "corrected_at"])

    print(f"store-sales: {DAYS} nights {first} to {last}, {total:,} rows; "
          f"last night {len(rows):,} rows, one-store {len(one):,} ({len(one) / len(rows):.1%}), "
          f"North {north_rows:,} ({north_rows / len(rows):.1%})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: make-store-sales.py <OUTDIR> [LAST_NIGHT]")
    last = (date.fromisoformat(sys.argv[2]) if len(sys.argv) > 2
            else date.today() - timedelta(days=1))
    main(Path(sys.argv[1]), last)
