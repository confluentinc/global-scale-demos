import os
import random
import sys
import threading
import time
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from confluent_kafka import Producer
from confluent_kafka.serialization import StringSerializer, SerializationContext, MessageField
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.json_schema import JSONSerializer

# metro_network.py is a shared module one directory up (see its own docstring
# for why it isn't duplicated into producer/ and live-map/ separately) -- same
# sys.path pattern live-map/server.py uses to reach the same file.
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from metro_network import (  # noqa: E402
    METRO_LINES,
    LINE_CODES,
    HUB_STATIONS,
    SEGMENT_TIMES,
    build_route,
    cumulative_times,
    leg_index_for_offset,
)

load_dotenv()

# === Confluent Cloud configuration ===
config = {
    'bootstrap.servers': os.environ['BOOTSTRAP_SERVER'],
    'security.protocol': 'SASL_SSL',
    'sasl.mechanisms': 'PLAIN',
    'sasl.username': os.environ['KAFKA_API_KEY'],
    'sasl.password': os.environ['KAFKA_API_SECRET'],
    'client.id': 'metro-camera-sensor',
}

TOPIC = os.environ.get('TOPIC', 'metro-camera-events')
# Real gap between two consecutive trains on the same line + direction (headway),
# not station-to-station travel time. A real metro's peak headway is closer
# to 3-4 minutes; 600s (10 min) matches what was explicitly requested here.
TRAIN_HEADWAY_SECONDS = int(os.environ.get('TRAIN_HEADWAY_SECONDS', 600))
# Multiplies every real-world sleep duration (segment travel times, headway-derived
# fleet spacing) for fast local smoke-testing. Leave at 1.0 for a true real-time run;
# e.g. 0.05 compresses a 2-minute hop into ~6s without changing the underlying
# realistic segment-time / headway model.
TIME_SCALE = float(os.environ.get('TIME_SCALE', 1.0))
COACHES_PER_TRAIN = 8

# Demo aid for the Phase 2 surge-detection pipeline (terraform/surge-detection.tf):
# periodically boosts headcount at one real (line, direction, station) so there's
# something real to detect, rather than waiting for organic ridership variance to
# happen to cross the 2.0x-baseline threshold on its own. Ties into
# enable_surge_detection via docker.tf's ENABLE_SURGE_INJECTION env var.
ENABLE_SURGE_INJECTION = os.environ.get('ENABLE_SURGE_INJECTION', 'true').lower() == 'true'
SURGE_INTERVAL_SECONDS = int(os.environ.get('SURGE_INTERVAL_SECONDS', 300))
SURGE_BOOST = float(os.environ.get('SURGE_BOOST', 4.0))
# Deliberately NOT scaled by TIME_SCALE -- Flink's 5-minute tumbling windows
# always key off real event time, no matter how fast the producer is
# simulating train movement, so a boost window sized (or scaled) to
# TIME_SCALE could otherwise end before a single real train passes through.
# Sized to exactly 1x the real headway (not 2x): long enough that a real
# departure from the targeted station is still virtually guaranteed to land
# inside the boosted window, but short enough that a single injected event
# typically only spans ~1-2 of Flink's 5-minute windows instead of ~4 --
# cutting repeated Bedrock calls for what is really just one surge event,
# not several.
SURGE_DURATION_SECONDS = int(os.environ.get('SURGE_DURATION_SECONDS', TRAIN_HEADWAY_SECONDS))

# JSON Schema for the payload, registered against Schema Registry so Flink SQL
# ('value.format' = 'json-registry') can deserialize these records natively.
# Single source of truth shared with terraform/schema.tf (which registers this
# same file via a confluent_schema resource *before* the Flink statements run
# -- Flink needs the schema to already exist to know the topic's columns, and
# can't wait on the producer registering it lazily at its own runtime).
with open(os.path.join(HERE, "schemas", "metro-camera-events-value.json")) as _f:
    EVENT_SCHEMA = _f.read()

schema_registry_client = SchemaRegistryClient({
    'url': os.environ['SCHEMA_REGISTRY_URL'],
    'basic.auth.user.info': f"{os.environ['SCHEMA_REGISTRY_API_KEY']}:{os.environ['SCHEMA_REGISTRY_API_SECRET']}",
})
json_serializer = JSONSerializer(EVENT_SCHEMA, schema_registry_client)
key_serializer = StringSerializer('utf_8')

producer = Producer(config)
producer_lock = threading.Lock()


def delivery_report(err, _msg):
    if err is not None:
        print(f"Message delivery failed: {err}")


IST = timezone(timedelta(hours=5, minutes=30))


def ist_now():
    """Current real time expressed in IST, independent of the host machine's timezone."""
    return datetime.now(IST)


def rush_hour_multiplier(dt):
    """Crowd multiplier reflecting real metro ridership patterns through the day."""
    hour = dt.hour + dt.minute / 60
    if 8.0 <= hour < 10.5 or 17.5 <= hour < 20.5:
        return random.uniform(1.6, 2.0)   # morning / evening peak
    if 6.0 <= hour < 8.0 or 20.5 <= hour < 22.5:
        return random.uniform(1.0, 1.3)   # shoulder hours
    if 10.5 <= hour < 17.5:
        return random.uniform(0.8, 1.1)   # daytime off-peak
    return random.uniform(0.25, 0.45)     # late night, sparse service


surge_lock = threading.Lock()
active_surges = {}  # (line, direction, station) -> real wall-clock expiry (time.time())

# Fixed rotation through a handful of real, well-known interchange stations
# (verified against metro_network.py's HUB_STATIONS), rather than a fresh
# random pick every cycle. Two reasons: (1) ML_DETECT_ANOMALIES' per-partition
# ARIMA model only matures after minTrainingSize of *that exact* (line,
# direction, station)'s own 5-minute windows (see 05_station_anomaly_scores.sql)
# -- repeatedly cycling through the same few partitions gets each of them
# through that warm-up window (and re-surged) far more reliably than hoping a
# fully random pick among ~400 partitions happens to already be mature; (2) a
# demo is easier to watch when the same few named stations light up in
# rotation instead of a different random one each time.
DEMO_SURGE_TARGETS = [
    ("Yellow_Line", "UP", "Rajiv Chowk"),
    ("Blue_Line", "DOWN", "Rajiv Chowk"),
    ("Red_Line", "UP", "Kashmere Gate"),
    ("Violet_Line", "DOWN", "Central Secretariat"),
    ("Orange_Line", "UP", "New Delhi"),
]


def surge_injector(stop_event):
    """
    Every SURGE_INTERVAL_SECONDS of real wall-clock time, boosts headcount at
    the next station in DEMO_SURGE_TARGETS by SURGE_BOOST for
    SURGE_DURATION_SECONDS -- see the module-level comment above those
    constants for why both are real-time, not TIME_SCALE-scaled.
    """
    i = 0
    while not stop_event.wait(SURGE_INTERVAL_SECONDS):
        line, direction, station = DEMO_SURGE_TARGETS[i % len(DEMO_SURGE_TARGETS)]
        i += 1
        key = (line, direction, station)
        with surge_lock:
            active_surges[key] = time.time() + SURGE_DURATION_SECONDS
        print(
            f"[surge-injector] {line} {direction} at {station}: "
            f"boosting headcount {SURGE_BOOST}x for {SURGE_DURATION_SECONDS}s"
        )


def surge_multiplier(line, direction, station):
    key = (line, direction, station)
    now = time.time()
    with surge_lock:
        expires_at = active_surges.get(key)
        if expires_at is None:
            return 1.0
        if now >= expires_at:
            del active_surges[key]
            return 1.0
        return SURGE_BOOST


def generate_departure_event(train):
    """
    Fires one payload per coach for this train, only at the moment doors lock
    and the train pulls out of the current station.
    """
    leg = train["route"][train["leg_idx"]]
    now = ist_now()
    timestamp = now.isoformat()

    multiplier = rush_hour_multiplier(now)
    is_hub = leg["station"] in HUB_STATIONS
    # Real DMRC coaches comfortably carry 100-200+ passengers at normal-to-busy
    # loading (crush load on a standard coach is closer to 300); bumped once
    # already from an original 12-42/coach range, then again slightly higher
    # here so peak-hour hub stations sit closer to that 100-200+ band instead
    # of just below it.
    base_per_coach = random.uniform(90, 150) if is_hub else random.uniform(45, 75)
    surge_boost = surge_multiplier(train["metro_line"], train["direction"], leg["station"])

    for coach_num in range(1, COACHES_PER_TRAIN + 1):
        headcount = round(base_per_coach * multiplier * surge_boost + random.uniform(-12, 12))
        payload = {
            "event_type": "DOOR_CLOSE_DEPARTURE",
            "timestamp": timestamp,
            "metadata": {
                "metro_line": train["metro_line"],
                "train_id": train["train_id"],
                "direction": train["direction"],
                "coach_number": f"C{coach_num}",
            },
            "location": {
                "current_station": leg["station"],
                "next_station": leg["next_station"],
            },
            "telemetry": {
                "headcount": max(0, headcount),
                "doors_locked": True,
                "speed_kmh": round(random.uniform(7.5, 9.5), 1),
            },
        }
        # Partitioning strategy: key by train_id so all coach telemetry for this
        # train lands in the same Kafka partition, preserving temporal order for
        # downstream Flink per-train aggregation.
        ctx = SerializationContext(TOPIC, MessageField.VALUE)
        with producer_lock:
            producer.produce(
                topic=TOPIC,
                key=key_serializer(train["train_id"]),
                value=json_serializer(payload, ctx),
                on_delivery=delivery_report,
            )
    with producer_lock:
        producer.flush()

    print(
        f"[{train['metro_line']}] {train['train_id']} ({train['direction']}) "
        f"departed {leg['station']} -> {leg['next_station']}"
    )


def train_worker(train, stop_event):
    stations = METRO_LINES[train["metro_line"]]
    segment_times = SEGMENT_TIMES[train["metro_line"]]
    while not stop_event.is_set():
        travel_seconds = train["route"][train["leg_idx"]]["travel_seconds"]
        generate_departure_event(train)
        if stop_event.wait(travel_seconds * TIME_SCALE):
            break
        train["leg_idx"] += 1
        if train["leg_idx"] >= len(train["route"]):
            # Reached the terminus: same physical train reverses direction.
            train["direction"] = "DOWN" if train["direction"] == "UP" else "UP"
            train["route"] = build_route(stations, segment_times, train["direction"])
            train["leg_idx"] = 0


def build_fleet():
    """
    Derive a realistic snapshot of trains already in service: enough trains per
    line per direction to maintain TRAIN_HEADWAY_SECONDS between consecutive
    trains across the line's full real run time, each positioned according to
    how far into the route it would be given its dispatch offset.
    """
    fleet = []
    for line, stations in METRO_LINES.items():
        code = LINE_CODES[line]
        segment_times = SEGMENT_TIMES[line]
        total_run_seconds = sum(segment_times)
        num_trains = max(1, round(total_run_seconds / TRAIN_HEADWAY_SECONDS))
        counter = 1
        for direction in ("UP", "DOWN"):
            route = build_route(stations, segment_times, direction)
            cum = cumulative_times([leg["travel_seconds"] for leg in route])
            for i in range(num_trains):
                offset = i * TRAIN_HEADWAY_SECONDS
                fleet.append({
                    "train_id": f"DL-{code}-{counter:03d}",
                    "metro_line": line,
                    "direction": direction,
                    "route": route,
                    "leg_idx": leg_index_for_offset(cum, offset),
                })
                counter += 1
    return fleet


if __name__ == "__main__":
    print(f"Initializing simulated metro edge cameras ({len(METRO_LINES)} lines)...")
    print(f"Train headway: {TRAIN_HEADWAY_SECONDS}s | Time scale: {TIME_SCALE}x")
    for _line, _times in SEGMENT_TIMES.items():
        _num_trains = max(1, round(sum(_times) / TRAIN_HEADWAY_SECONDS))
        print(
            f"  {_line}: {len(_times)} segments, real run time {sum(_times) // 60} min, "
            f"avg hop {round(sum(_times) / len(_times))}s, {_num_trains} trains/direction"
        )

    fleet = build_fleet()
    stop_event = threading.Event()
    threads = [
        threading.Thread(target=train_worker, args=(train, stop_event), daemon=True)
        for train in fleet
    ]
    if ENABLE_SURGE_INJECTION:
        print(f"Surge injector: every {SURGE_INTERVAL_SECONDS}s (real time), {SURGE_BOOST}x for {SURGE_DURATION_SECONDS}s")
        threads.append(threading.Thread(target=surge_injector, args=(stop_event,), daemon=True))

    try:
        for t in threads:
            t.start()
            time.sleep(0.05)  # spread initial flush() calls instead of a startup burst
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping producer...")
        stop_event.set()
        for t in threads:
            t.join(timeout=2)
        producer.flush()
        print("Producer stopped.")
