import time
import uuid
import random
import configparser
from datetime import datetime, timezone

from faker import Faker
from pymongo import MongoClient, UpdateOne
from pymongo.errors import PyMongoError

# Initialize Faker
fake = Faker()

# Geographically accurate mapping
REGIONS = {
    "US": [
        {"city": "New York", "state": "NY", "country": "United States"},
        {"city": "Los Angeles", "state": "CA", "country": "United States"},
        {"city": "Chicago", "state": "IL", "country": "United States"}
    ],
    "EU": [
        {"city": "London", "state": "Greater London", "country": "United Kingdom"},
        {"city": "Paris", "state": "Ile-de-France", "country": "France"},
        {"city": "Berlin", "state": "Berlin", "country": "Germany"}
    ],
    "APAC": [
        {"city": "Tokyo", "state": "Tokyo", "country": "Japan"},
        {"city": "Mumbai", "state": "Maharashtra", "country": "India"},
        {"city": "Sydney", "state": "New South Wales", "country": "Australia"}
    ]
}

CATEGORIES = ["bill", "payment", "shopping", "emi", "insurance", "medical", "entertainment", "travel", "groceries"]
PAYMENT_METHODS = ["UPI", "SWIFT", "CREDIT CARD", "DEBIT CARD", "WALLET", "NET BANKING"]

# State dictionaries to manage user profiles dynamically (Only for the active pool)
USER_NAME_MAP = {}
USER_ACCOUNT_MAP = {}
USER_DEVICE_MAP = {}
USER_HOME_REGION = {}
USER_HOME_LOCATION = {}


def get_mongo_client(config, max_retries=None, initial_backoff=2):
    """Connects to MongoDB with exponential-backoff retries (mirrors the original
    Postgres retry loop so the container survives a slow-starting Atlas cluster)."""
    retries = 0
    backoff = initial_backoff
    uri = config.get('mongodb', 'uri')
    while True:
        try:
            client = MongoClient(uri, serverSelectionTimeoutMS=5000)
            client.admin.command("ping")
            return client
        except PyMongoError as e:
            retries += 1
            if max_retries is not None and retries > max_retries:
                print(f"\n[DB ERROR] Maximum connection retries ({max_retries}) reached.")
                raise e
            print(f"\n[DB TIMEOUT] MongoDB not reachable yet: {e}")
            print(f"Retrying in {backoff} seconds... (Attempt {retries})")
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)


def ensure_collections(db):
    """Creates the collections/indexes if missing. Change streams (used by the CDC
    connector) work against any existing collection, so this just makes lookups fast."""
    print("Checking database layout definitions...")
    if "user_profiles" not in db.list_collection_names():
        db.create_collection("user_profiles")
    if "payments" not in db.list_collection_names():
        db.create_collection("payments")
    db.user_profiles.create_index("home_region")
    db.payments.create_index("user_id")
    print("MongoDB layout verified successfully (`user_profiles` and `payments` ready).")


def bulk_create_users(user_ids, db, update_memory_maps=True):
    """Generates and bulk-upserts multiple users into MongoDB in a single batch."""
    operations = []

    for user_id in user_ids:
        full_name = fake.name()
        associated_accounts = [fake.bban() for _ in range(random.randint(1, 3))]
        device_id = str(uuid.uuid4())

        home_region = random.choice(list(REGIONS.keys()))
        location = random.choice(REGIONS[home_region])

        credit_cards = [fake.credit_card_number() for _ in range(random.randint(1, 2))]
        pii_email = fake.unique.email()
        pii_phone = fake.phone_number()
        pii_ssn = fake.ssn()
        pii_dob = fake.date_of_birth(minimum_age=18, maximum_age=75).isoformat()

        if update_memory_maps:
            USER_NAME_MAP[user_id] = full_name
            USER_ACCOUNT_MAP[user_id] = associated_accounts
            USER_DEVICE_MAP[user_id] = device_id
            USER_HOME_REGION[user_id] = home_region
            USER_HOME_LOCATION[user_id] = location

        document = {
            "_id": user_id,
            "user_id": user_id,
            "full_name": full_name,
            "device_id": device_id,
            "home_region": home_region,
            "home_city": location["city"],
            "home_state": location["state"],
            "home_country": location["country"],
            "associated_accounts": associated_accounts,
            "credit_cards": credit_cards,
            "email": pii_email,
            "phone_number": pii_phone,
            "ssn_or_tax_id": pii_ssn,
            "date_of_birth": pii_dob,
            "created_at": datetime.now(timezone.utc),
        }
        operations.append(UpdateOne({"_id": user_id}, {"$setOnInsert": document}, upsert=True))

    try:
        result = db.user_profiles.bulk_write(operations, ordered=False)
        print(f"Successfully upserted {result.upserted_count} new users into MongoDB.")
    except PyMongoError as e:
        print(f"Warning: could not write new profile batch to MongoDB: {e}")


def initialize_user_pool(pool_size, db):
    """Initializes the baseline minimum active user pool on startup using bulk upserts."""
    user_pool = [f"user_{str(i).zfill(4)}" for i in range(1, pool_size + 1)]
    print(f"Initializing baseline transaction pool of {pool_size} users...")
    bulk_create_users(user_pool, db, update_memory_maps=True)
    print("Baseline active pool successfully built and saved to MongoDB.")
    return user_pool


def get_transaction_location(user_id, is_anomaly):
    if is_anomaly:
        home_region = USER_HOME_REGION[user_id]
        alternate_regions = [r for r in REGIONS.keys() if r != home_region]
        target_region = random.choice(alternate_regions)
        return random.choice(REGIONS[target_region])
    else:
        return USER_HOME_LOCATION[user_id]


def main():
    config = configparser.ConfigParser()
    config.read('config.ini')

    target_tps = config.getint('simulation', 'target_tps')
    valid_percentage = config.getfloat('simulation', 'valid_transaction_percentage')
    user_pool_size = config.getint('simulation', 'user_pool_size')

    anomaly_threshold = valid_percentage / 100.0

    client = get_mongo_client(config, max_retries=None)
    db = client[config.get('mongodb', 'database', fallback='finintel')]

    ensure_collections(db)

    user_pool = initialize_user_pool(user_pool_size, db)
    next_user_index = user_pool_size + 1

    print(f"Streaming data at {target_tps} TPS...")
    interval = 1.0 / target_tps

    last_user_addition_time = time.time()
    user_addition_interval = 60.0  # 1 minute

    try:
        while True:
            start_time = time.time()

            # --- BACKGROUND USER GROWTH ENGINE (1 new user / minute) ---
            if start_time - last_user_addition_time >= user_addition_interval:
                new_user_id = f"user_{str(next_user_index).zfill(4)}"
                print(f"\n[User Growth] Writing new registration: {new_user_id}")
                bulk_create_users([new_user_id], db, update_memory_maps=False)
                next_user_index += 1
                last_user_addition_time = start_time

            # --- SIMULATION EVENT ENGINE ---
            payer_id = random.choice(user_pool)
            payee_id = random.choice([u for u in user_pool if u != payer_id])

            user_name = USER_NAME_MAP[payer_id]
            payer_account = random.choice(USER_ACCOUNT_MAP[payer_id])
            payee_account = random.choice(USER_ACCOUNT_MAP[payee_id])
            device_id = USER_DEVICE_MAP[payer_id]

            category = random.choice(CATEGORIES)
            payment_method = random.choice(PAYMENT_METHODS)

            is_anomaly = random.random() > anomaly_threshold
            location = get_transaction_location(payer_id, is_anomaly)

            if is_anomaly and random.random() > 0.90:
                device_id = str(uuid.uuid4())
                amount = float(random.randint(2500, 15000))
            elif is_anomaly:
                amount = float(random.randint(2500, 15000))
            else:
                amount = float(fake.random_int(min=5, max=1000))

            transaction_id = str(uuid.uuid4())
            payment_document = {
                "_id": transaction_id,
                "transaction_id": transaction_id,
                "user_id": payer_id,
                "user_name": user_name,
                "device_id": device_id,
                "payer_account_no": payer_account,
                "payee_account_no": payee_account,
                "category": category,
                "payment_method": payment_method,
                "amount": amount,
                "currency": "USD",
                "timestamp": datetime.now(timezone.utc),
                "address": {
                    "city": location["city"],
                    "state": location["state"],
                    "country": location["country"],
                },
            }

            try:
                db.payments.insert_one(payment_document)
            except PyMongoError as e:
                print(f"Warning: could not write transaction to MongoDB: {e}")

            elapsed = time.time() - start_time
            sleep_time = interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\nStopping stream...")
    finally:
        client.close()


if __name__ == "__main__":
    main()
