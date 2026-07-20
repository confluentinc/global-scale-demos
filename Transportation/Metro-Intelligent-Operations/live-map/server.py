"""
Live Delhi Metro map backend: consumes the raw metro-camera-events topic,
tracks live per-train state and per-segment headcount totals, and serves both
the static frontend and a WebSocket feed of the current snapshot.

Deserialization note: the producer writes messages via confluent_kafka's
JSONSerializer, which frames each value as [1 magic byte][4-byte schema id]
[JSON bytes] (the standard Confluent wire format). JSON is self-describing, so
unlike Avro/Protobuf we don't need the Schema Registry to decode it -- we just
strip that 5-byte header and json.loads() the rest.

Optionally (if Phase 2 / enable_surge_detection is deployed -- see
../terraform/surge-detection.tf) also consumes metro_station_surge_anomalies,
Flink's own output table of real, already-detected station-level surges. That
table is explicitly created with 'value.format' = 'json-registry'
(../flink-sql/06_station_surge_anomalies.sql) specifically so it decodes with
the exact same trick as above -- this server still never needs Schema
Registry credentials for anything.
"""
import asyncio
import json
import os
import sys
import threading
import time
from collections import defaultdict

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from confluent_kafka import Consumer

HERE = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(HERE, "..", ".env"))

# metro_network.py is pure data/logic (no env vars, no Kafka/Schema-Registry
# clients) -- safe to import here without needing any producer credentials.
sys.path.insert(0, os.path.join(HERE, ".."))
from metro_network import METRO_LINES, LINE_COLORS, SEGMENT_TIMES  # noqa: E402

with open(os.path.join(HERE, "stations.json")) as f:
    STATIONS = json.load(f)

# Average real hop duration per line -- matches metro_network.py's own
# calibration (LINE_TOTAL_RUN_SECONDS / segment count), used by the frontend
# to animate a train's position between current_station and next_station.
LINE_AVG_HOP_SECONDS = {
    line: round(sum(times) / len(times))
    for line, times in SEGMENT_TIMES.items()
}

TOPIC = os.environ.get("TOPIC", "metro-camera-events")
# A train is dropped from the live view if we haven't seen a new departure
# event for it in this long (producer stopped, or the train reached a terminus
# and is turning around).
STALE_AFTER_SECONDS = 20 * 60

SURGE_TOPIC = os.environ.get("SURGE_TOPIC", "metro_station_surge_anomalies")
ENABLE_SURGE_HIGHLIGHTS = os.environ.get("ENABLE_SURGE_HIGHLIGHTS", "true").lower() == "true"
# Flink re-evaluates each (line, direction, station) every 5-minute window
# (see ../flink-sql/04_station_headcounts.sql); a surge is kept highlighted
# for a bit longer than that so it doesn't flicker off between windows, and
# disappears on its own once no new surge row arrives for it.
SURGE_TTL_SECONDS = 6 * 60

CONSUMER_CONFIG = {
    "bootstrap.servers": os.environ["BOOTSTRAP_SERVER"],
    "security.protocol": "SASL_SSL",
    "sasl.mechanisms": "PLAIN",
    "sasl.username": os.environ["KAFKA_API_KEY"],
    "sasl.password": os.environ["KAFKA_API_SECRET"],
    "group.id": "metro-live-map-viewer",
    "auto.offset.reset": "latest",
}

state_lock = threading.Lock()
trains = {}  # train_id -> live state dict
surges = {}  # (metro_line, direction, current_station) -> live state dict


def decode_json_schema_message(value_bytes):
    return json.loads(value_bytes[5:])


def handle_event(payload):
    meta = payload["metadata"]
    loc = payload["location"]
    telem = payload["telemetry"]
    train_id = meta["train_id"]
    timestamp = payload["timestamp"]

    with state_lock:
        existing = trains.get(train_id)
        if existing is None or existing["timestamp"] != timestamp:
            # First coach seen for this departure: reset the running sum.
            trains[train_id] = {
                "train_id": train_id,
                "metro_line": meta["metro_line"],
                "direction": meta["direction"],
                "current_station": loc["current_station"],
                "next_station": loc["next_station"],
                "timestamp": timestamp,
                "headcount": telem["headcount"],
                "coach_count": 1,
                "received_at": time.time(),
            }
        else:
            existing["headcount"] += telem["headcount"]
            existing["coach_count"] += 1


def handle_surge_event(payload):
    key = (payload["metro_line"], payload["direction"], payload["current_station"])
    with state_lock:
        surges[key] = {
            "metro_line": payload["metro_line"],
            "direction": payload["direction"],
            "current_station": payload["current_station"],
            "total_headcount": payload["total_headcount"],
            "baseline_avg": payload["baseline_avg"],
            "active_trains": payload["active_trains"],
            "received_at": time.time(),
        }


def consume_loop():
    consumer = Consumer(CONSUMER_CONFIG)
    topics = [TOPIC] + ([SURGE_TOPIC] if ENABLE_SURGE_HIGHLIGHTS else [])
    consumer.subscribe(topics)
    print(f"[live-map] consuming {topics} as group 'metro-live-map-viewer'...")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print("[live-map] consumer error:", msg.error())
                continue
            try:
                payload = decode_json_schema_message(msg.value())
                if msg.topic() == SURGE_TOPIC:
                    handle_surge_event(payload)
                else:
                    handle_event(payload)
            except Exception as exc:
                print("[live-map] failed to process message:", exc)
    finally:
        consumer.close()


def compute_snapshot():
    now = time.time()
    with state_lock:
        active = [dict(t) for t in trains.values() if now - t["received_at"] <= STALE_AFTER_SECONDS]
        active_surges = [dict(s) for s in surges.values() if now - s["received_at"] <= SURGE_TTL_SECONDS]

    surge_list = []
    for s in active_surges:
        station = STATIONS.get(s["current_station"])
        if not station:
            continue
        surge_list.append({**s, "lat": station["lat"], "lng": station["lng"]})

    segment_totals = defaultdict(int)
    segment_trains = defaultdict(int)
    for t in active:
        key = (t["metro_line"], t["direction"], t["current_station"], t["next_station"])
        segment_totals[key] += t["headcount"]
        segment_trains[key] += 1

    segments = [
        {
            "metro_line": line,
            "direction": direction,
            "current_station": current,
            "next_station": nxt,
            "headcount": segment_totals[(line, direction, current, nxt)],
            "trains_counted": segment_trains[(line, direction, current, nxt)],
        }
        for (line, direction, current, nxt) in segment_totals
    ]

    return {"server_time": now, "trains": active, "segments": segments, "surges": surge_list}


app = FastAPI()


@app.on_event("startup")
def on_startup():
    threading.Thread(target=consume_loop, daemon=True).start()


@app.get("/api/stations")
def get_stations():
    return STATIONS


@app.get("/api/lines")
def get_lines():
    return {
        "lines": METRO_LINES,
        "colors": LINE_COLORS,
        "hop_seconds": LINE_AVG_HOP_SECONDS,
    }


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            await websocket.send_json(compute_snapshot())
            await asyncio.sleep(1.0)
    except WebSocketDisconnect:
        pass


app.mount("/", StaticFiles(directory=os.path.join(HERE, "static"), html=True), name="static")
