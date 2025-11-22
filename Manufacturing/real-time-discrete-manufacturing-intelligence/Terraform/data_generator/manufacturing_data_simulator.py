# Steps to run this file
# python3 -m venv path/to/venv
# source path/to/venv/bin/activate
# python3 -m pip install psycopg2-binary faker
# python3 manufacturing_data_simulator.py

import psycopg2
import random
import time
import uuid
from datetime import datetime, timedelta, timezone
from faker import Faker
from psycopg2 import sql
from dotenv import load_dotenv
import os

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------

DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": 5432,
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD")
}

TOTAL_EVENTS = 5000
EVENT_INTERVAL = 0.1  # High speed generation
faker = Faker()

ROUTING_STAGES = ["Material Receipt", "Pre-Processing", "Fabrication", "Assembly", "Quality Inspection", "Packing"]

# ---------------------------------------------------------
# DATABASE SETUP
# ---------------------------------------------------------
def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def reset_tables():
    """
    Clean data only. We do NOT drop tables to preserve Terraform/Connector configuration.
    """
    conn = get_connection()
    cur = conn.cursor()
    try:
        # Order matters due to Foreign Key constraints
        # 1. Clear streaming data & metrics
        tables_to_clear = [
            "sensor_events",
            "production_metrics_sink",
            "production_metrics_history"
        ]
        for table in tables_to_clear:
            cur.execute(sql.SQL("TRUNCATE TABLE {} RESTART IDENTITY CASCADE;").format(sql.Identifier(table)))

        # 2. Clear reference data
        cur.execute("TRUNCATE TABLE work_orders RESTART IDENTITY CASCADE;")

        conn.commit()
        print("[INFO] ✅ Tables truncated. Ready for fresh simulation.")
    except Exception as e:
        print(f"[ERROR] ❌ Failed to truncate tables: {e}")
        conn.rollback()
    finally:
        cur.close()
        conn.close()

def create_sample_work_orders():
    now = datetime.now(timezone.utc)
    # workorder_id, category, code, planned_qty, start, end
    work_orders = [
        ("WO-2025-001", "Engine", "PRD-1001", 5000, now - timedelta(hours=2), now + timedelta(hours=6)),
        ("WO-2025-002", "Electrical", "PRD-1002", 4000, now - timedelta(hours=1), now + timedelta(hours=5)),
        ("WO-2025-003", "Chassis", "PRD-1003", 6000, now, now + timedelta(hours=8)),
        ("WO-2025-004", "Body", "PRD-1004", 3500, now, now + timedelta(hours=7)),
        ("WO-2025-005", "Paint", "PRD-1005", 3000, now + timedelta(hours=1), now + timedelta(hours=9))
    ]

    conn = get_connection()
    cur = conn.cursor()
    insert_query = """
        INSERT INTO work_orders (workorder_id, product_category, product_code, planned_quantity, start_date, end_date)
        VALUES (%s, %s, %s, %s, %s, %s);
    """
    cur.executemany(insert_query, work_orders)
    conn.commit()
    cur.close()
    conn.close()
    return [w[0] for w in work_orders]

# ---------------------------------------------------------
# GENERATOR LOGIC
# ---------------------------------------------------------
def generate_sensor_event(workorder_ids):
    workorder_id = random.choice(workorder_ids)
    item_id = str(uuid.uuid4())
    batch_number = f"BATCH-{random.randint(1,10):02d}"
    line_number = f"LINE-{random.randint(1,5)}"
    routing_stage = random.choice(ROUTING_STAGES)
    operator_id = f"OP{random.randint(100, 120)}"

    # Simulate Physics
    temperature = round(random.gauss(80, 15), 2)
    pressure = round(random.gauss(120, 20), 2)

    # Defect Logic
    is_defective = False
    defect_reason = None

    if temperature > 110:
        is_defective = True
        defect_reason = "Thermal Issue"
    elif pressure > 160 or pressure < 80:
        is_defective = True
        defect_reason = "Pressure Variance"
    elif random.random() < 0.05:
        is_defective = True
        defect_reason = random.choice(["Alignment Error", "Material Fracture", "Software Glitch"])

    event = {
        "workorder_id": workorder_id,
        "item_id": item_id,
        "batch_number": batch_number,
        "line_number": line_number,
        "routing_stage": routing_stage,
        "temperature": temperature,
        "pressure": pressure,
        "is_defective": is_defective,
        "defect_reason": defect_reason,
        "operator_id": operator_id,
        "sensor_timestamp": datetime.now(timezone.utc)
    }
    return event

def insert_sensor_event(event):
    conn = get_connection()
    cur = conn.cursor()
    # Note: 'event_id' is SERIAL, so we do not insert it manually.
    insert_query = """
        INSERT INTO sensor_events (
            workorder_id, item_id, batch_number, line_number, routing_stage,
            temperature, pressure, is_defective, defect_reason, operator_id, sensor_timestamp
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);
    """
    cur.execute(insert_query, (
        event["workorder_id"], event["item_id"], event["batch_number"],
        event["line_number"], event["routing_stage"], event["temperature"],
        event["pressure"], event["is_defective"], event["defect_reason"],
        event["operator_id"], event["sensor_timestamp"]
    ))
    conn.commit()
    cur.close()
    conn.close()

if __name__ == "__main__":
    print("[INFO] Starting Discrete Manufacturing Simulator...")

    # 1. Clear old data (Does not drop tables)
    reset_tables()

    # 2. Create Metadata
    workorder_ids = create_sample_work_orders()

    # 3. Stream Data
    print(f"[INFO] Streaming {TOTAL_EVENTS} item events...")
    for i in range(1, TOTAL_EVENTS + 1):
        event = generate_sensor_event(workorder_ids)
        insert_sensor_event(event)
        if i % 100 == 0:
            print(f"[{i}] Item: {event['item_id']} | Defective: {event['is_defective']}")
        time.sleep(EVENT_INTERVAL)