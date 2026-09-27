#!/usr/bin/env python3
"""
Generate the Session 6 point-of-sale extracts.

    python3 make-sample.py <OUTDIR>

Writes two files that differ by exactly three rows:

    pos-2026-09-24.csv        20,000 well-formed transactions
    pos-2026-09-24-dirty.csv  the same 20,000 rows, plus three the source
                              system should never have sent

The generator is seeded, so a re-capture produces byte-identical files and the
row counts and byte counts quoted in RUNBOOK.md stay true.

The three bad rows are the three failure shapes the lecture names. One carries a
date the source system invented, one carries a non-numeric amount, and one
carries a negative quantity that is syntactically valid and semantically wrong.
The third is the interesting one, because no type system catches it.
"""

import csv
import random
import sys
from pathlib import Path

ROWS = 20_000
SEED = 61906
BUSINESS_DATE = "2026-09-24"

STORES = [f"CLT-{n:03d}" for n in range(1, 41)]
SKUS = [f"SKU-{n:05d}" for n in range(1000, 1120)]
HEADER = ["txn_id", "store_id", "txn_ts", "sku", "qty", "amount"]

# The three rows a well-behaved source system would never emit. Each one is a
# different failure category from Concept Block 1: a type violation, a second
# type violation in a different column, and a business-rule violation that is
# perfectly well typed.
BAD_ROWS = [
    ["T-0900001", "CLT-007", "not-a-date", "SKU-01042", "2", "18.50"],
    ["T-0900002", "CLT-013", f"{BUSINESS_DATE} 11:04:22", "SKU-01077", "1", "N/A"],
    ["T-0900003", "CLT-022", f"{BUSINESS_DATE} 15:41:09", "SKU-01003", "-4", "62.00"],
]


def rows():
    rng = random.Random(SEED)
    for n in range(ROWS):
        hh = rng.randrange(8, 21)
        mm = rng.randrange(0, 60)
        ss = rng.randrange(0, 60)
        yield [
            f"T-{n + 100000:07d}",
            rng.choice(STORES),
            f"{BUSINESS_DATE} {hh:02d}:{mm:02d}:{ss:02d}",
            rng.choice(SKUS),
            str(rng.randrange(1, 6)),
            f"{rng.uniform(2.5, 240.0):.2f}",
        ]


def write(path: Path, extra: list) -> None:
    with path.open("w", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(HEADER)
        for row in rows():
            w.writerow(row)
        for row in extra:
            w.writerow(row)


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "data")
    out.mkdir(parents=True, exist_ok=True)

    clean = out / f"pos-{BUSINESS_DATE}.csv"
    dirty = out / f"pos-{BUSINESS_DATE}-dirty.csv"
    write(clean, [])
    write(dirty, BAD_ROWS)

    for p in (clean, dirty):
        print(f"  {p}  {p.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
