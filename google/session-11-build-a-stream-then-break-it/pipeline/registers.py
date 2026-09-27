"""
Crown Street Markets register simulator.

    python registers.py <topic> burst [N]     N normal sales now, across 40 stores (default 200)
    python registers.py <topic> late          one sale from CLT-031 (Ballantyne) rung 30 minutes ago
    python registers.py <topic> duplicate     the same sale published twice, as a register retry does
    python registers.py <topic> malformed     a scanner firmware update sends total as "$3.49"

Every message carries two attributes: event_ts, when the sale was rung, and
sale_id, the register's own identifier for it. Pub/Sub assigns each publish
its own message ID, so a retried sale arrives twice with two message IDs and
one sale_id.
"""
import json
import random
import sys
import time
from datetime import datetime, timedelta, timezone

from google.cloud import pubsub_v1

topic, mode = sys.argv[1], sys.argv[2]
pub = pubsub_v1.PublisherClient()
rng = random.Random()


def send(sale, rung_at, sale_id):
    f = pub.publish(topic, json.dumps(sale).encode(),
                    event_ts=rung_at.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                    sale_id=sale_id)
    return f.result()


now = datetime.now(timezone.utc)
if mode == "burst":
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 200
    ids = [send({"store_id": f"CLT-{rng.randint(1, 40):03d}", "lane": rng.randint(1, 12),
                 "total": round(rng.uniform(2.5, 180), 2)}, now, f"S-{int(time.time()*1000)}-{i}")
           for i in range(n)]
    print(f"published {len(ids)} sales rung at {now:%H:%M:%S}Z")
elif mode == "late":
    rung = now - timedelta(minutes=30)
    mid = send({"store_id": "CLT-031", "lane": 4, "total": 412.18}, rung, f"S-LATE-{int(time.time())}")
    print(f"published one CLT-031 sale of $412.18 rung at {rung:%H:%M:%S}Z, message id {mid}")
elif mode == "duplicate":
    sid = f"S-DUP-{int(time.time())}"
    sale = {"store_id": "CLT-007", "lane": 2, "total": 88.40}
    a, b = send(sale, now, sid), send(sale, now, sid)
    print(f"published sale {sid} twice: message ids {a} and {b}")
elif mode == "malformed":
    mid = send({"store_id": "CLT-022", "lane": 9, "total": "$3.49"}, now, f"S-BAD-{int(time.time())}")
    print(f"published one CLT-022 sale with total \"$3.49\", message id {mid}")
