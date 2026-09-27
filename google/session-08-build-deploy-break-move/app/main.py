"""Queen City Trip Analytics · fare-quote API.

A fictional South End, Charlotte company's prediction service. Fleet
dispatch apps call /quote during business hours; the "model" is a small
coefficient table, and each quote does about 150 ms of CPU work so that CPU
limits are visible as latency.
"""
import hashlib
import os
import socket
import time

from flask import Flask, jsonify, request

VERSION = open(os.path.join(os.path.dirname(__file__), "VERSION")).read().strip()

# Simulated model load. STARTUP_SECONDS makes a new pod slow to become
# useful, which is what a readiness probe exists to hide.
time.sleep(float(os.environ.get("STARTUP_SECONDS", "0")))

# ALLOCATE_MB holds memory for the life of the process, which is how the
# demonstration produces OOMKilled against a small limit.
_ballast = bytearray(int(os.environ.get("ALLOCATE_MB", "0")) * 1024 * 1024)
for i in range(0, len(_ballast), 4096):
    _ballast[i] = 1

app = Flask(__name__)
BASE = {"v1": 3.00, "v2": 3.25}
PER_ZONE = 0.85


def _score(pickup: str, dropoff: str, work_ms: float = 150.0) -> float:
    """Burn roughly work_ms of CPU, the cost of one model inference."""
    end = time.process_time() + work_ms / 1000.0
    h = f"{pickup}:{dropoff}".encode()
    while time.process_time() < end:
        h = hashlib.sha256(h).digest()
    return abs(int(pickup or 0) - int(dropoff or 0)) % 40 + 1


@app.get("/quote")
def quote():
    start = time.time()
    pickup = request.args.get("pickup", "132")
    dropoff = request.args.get("dropoff", "236")
    zones = _score(pickup, dropoff)
    fare = round(BASE.get(VERSION, 3.0) + PER_ZONE * zones, 2)
    body = {"fare": fare, "model": VERSION, "pod": socket.gethostname(),
            "ms": round((time.time() - start) * 1000)}
    if VERSION == "v2":
        body["surge"] = 1.0
    return jsonify(body)


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/ready")
def ready():
    return "ready"


@app.get("/")
def root():
    return jsonify({"service": "fare-quote", "company": "Queen City Trip Analytics",
                    "model": VERSION})
