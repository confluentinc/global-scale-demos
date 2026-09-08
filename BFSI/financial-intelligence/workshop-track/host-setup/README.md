# Financial Intelligence Workshop — Host Guide

This is the instructor's guide. Attendees don't need this — they only need the
connection details you hand out (see [Handing out access](#handing-out-access)) and
the [attendee guide](../attendee-lab/README.md).

## Overview

Each attendee provisions their own Confluent Cloud environment and builds a real-time
financial intelligence pipeline by hand: two MongoDB Atlas Source connectors, three
Flink SQL statements, and Tableflow.

The only shared piece is the source data: a MongoDB instance, run by you, continuously
receiving simulated `user_profiles` and `payments` documents. Every attendee points
their own MongoDB Atlas Source connectors at that same Mongo instance (one connector
per collection), so everyone streams from one live, shared dataset into their own,
fully isolated Confluent Cloud cluster.

No AWS account is needed anywhere in this workshop, for you or attendees.

```
                     (you run this once, before + during the workshop)
   ┌────────────────────┐        change stream        ┌──────────────────────────────┐
   │  mongo_datagen.py   │ ───────────────────────────▶│  Shared MongoDB (Atlas)      │
   │  (datagen/)         │   user_profiles, payments   │  db: finintel                │
   └────────────────────┘                              └──────────────┬───────────────┘
                                                                        │
                                     each attendee configures their own │ MongoDB Atlas
                                     connectors (one per collection)    │ Source Connectors
                                     against the same Mongo instance    ▼
        ┌───────────────────────────────────────────────────────────────────────────┐
        │  Attendee's own Confluent Cloud Environment                              │
        │                                                                          │
        │   topics: cdc.finintel.user_profiles, cdc.finintel.payments              │
        │                       │                                                  │
        │                       ▼                                                  │
        │   Flink SQL: account_daily_ledger → fraudulent_alerts → upsell_opps      │
        │                       │                                                  │
        │                       ▼                                                  │
        │   Tableflow (Confluent-managed storage) on account_daily_ledger          │
        └───────────────────────────────────────────────────────────────────────────┘
```

## Suggested agenda (~2.5–3 hrs)

1. You: confirm the generator below has been running for a few minutes so there's
   backlog data to demo change-stream catch-up (10 min, before attendees arrive).
2. Attendees: Prerequisites (10 min)
3. Attendees: Confluent Cloud environment/cluster/compute pool (20 min)
4. Attendees: MongoDB Atlas Source connectors (25 min)
5. Attendees: Flink SQL pipeline (60 min)
6. Attendees: Tableflow (20 min)
7. Attendees: Cleanup (10 min)

All attendee-facing steps live in the [attendee guide](../attendee-lab/README.md).

## Before the day: verify the connector

Confluent Cloud's MongoDB Atlas Source connector's exact config field names can change
between console versions. Walk through the connector step once in the Confluent Cloud
UI yourself and correct the connector section of the
[attendee guide](../attendee-lab/README.md#step-3-mongodb-atlas-source-connector) if
anything has changed.

## The shared data feed

It runs a continuous data generator that writes simulated financial data straight into
a MongoDB database, which every attendee's own MongoDB Atlas Source connectors read
from during the lab.

### What it does

`datagen/mongo_datagen.py` writes simulated financial data directly into two MongoDB
collections:

- `finintel.user_profiles` — one document per simulated user, including PII fields
  (name, device ID, home address, linked accounts, card numbers).
- `finintel.payments` — one document per simulated transaction, including the
  occasional impossible-travel / device-switch / amount-anomaly patterns the Flink
  fraud statement is designed to catch.

It runs forever, at a configurable rate (`target_tps`), and slowly grows the user pool
over time — attendees connecting at different points in the workshop will see fresh
documents (and thus fresh Kafka records via CDC) as long as this keeps running.

### Prerequisites

1. A MongoDB instance reachable by every attendee's Confluent Cloud connector. The
   simplest option is a small **MongoDB Atlas** cluster (free/shared tier is enough for
   workshop TPS) with:
   - **Network access**: allow access from `0.0.0.0/0`, or from Confluent Cloud's
     published CONNECT egress IP ranges for your region — `0.0.0.0/0` is simplest for
     a short-lived workshop cluster.
   - A **read-only** database user for attendees (see below) in addition to the
     read-write user this generator uses.
   - Change streams require Atlas (or any replica set) — a standalone `mongod` will
     not work with the connector.
2. Docker, to build/run the generator container (or run it directly with Python 3.11+).

### Configure

```bash
cd host-setup/datagen
cp config.ini.example config.ini
```

Edit `config.ini`:

```ini
[mongodb]
uri      = mongodb+srv://<rw-user>:<password>@<your-atlas-cluster>.mongodb.net/
database = finintel

[simulation]
target_tps                   = 10
valid_transaction_percentage = 95.0
user_pool_size                = 100
```

### Run it

**Docker (recommended for a "leave it running all day" workshop host machine):**

```bash
docker compose up -d --build
docker compose logs -f
```

**Directly with Python:**

```bash
pip install -r requirements.txt
python mongo_datagen.py
```

Leave it running for the entire workshop. It's safe to `Ctrl+C` / stop the container
between sessions — on restart it reuses existing users (`ON CONFLICT`-style upsert
equivalent via Mongo's `_id` uniqueness) and keeps growing the pool and streaming
payments.

## Handing out access

Give each attendee, before Step 3 of the attendee guide:

- The Mongo **connection string** using a **read-only** database user (create one
  in Atlas: Database Access → Add New Database User → built-in role `read` scoped to
  the `finintel` database). Never hand out the read-write credentials this generator
  uses.
- The **database name** (`finintel`) and **collection names**
  (`user_profiles`, `payments`).

Every attendee's connector reads the exact same collections — the shared dataset is
part of the exercise (they'll all see each other's simulated "impossible travel"
alerts fire on the same underlying data, which is a fine talking point).

## Cleanup after the workshop

```bash
docker compose down
```

Then delete or pause the Atlas cluster if it was created solely for this workshop.
