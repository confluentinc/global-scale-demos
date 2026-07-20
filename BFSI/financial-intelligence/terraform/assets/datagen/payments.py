import time
import uuid
import random
import configparser
import psycopg2
from psycopg2.extras import execute_values
from psycopg2 import OperationalError, InterfaceError
from faker import Faker
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

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

def get_db_connection(config):
    """Establishes connection to Postgres using configurations with a strict 5-second timeout footprint."""
    return psycopg2.connect(
        host=config.get('postgresql', 'host', fallback='localhost'),
        database=config.get('postgresql', 'database', fallback='payments_db'),
        user=config.get('postgresql', 'user', fallback='postgres'),
        password=config.get('postgresql', 'password', fallback='postgres'),
        port=config.get('postgresql', 'port', fallback='5432'),
        connect_timeout=5  # Fast failure trigger to let retry handle timeouts smoothly
    )

def execute_db_with_retry(config, db_action_func, *args, max_retries=None, initial_backoff=2):
    """
    Executes a given database operation context. Retries smoothly using 
    exponential backoff if an Operational or Interface connection timeout occurs.
    """
    retries = 0
    backoff = initial_backoff
    
    while True:
        conn = None
        try:
            conn = get_db_connection(config)
            result = db_action_func(conn, *args)
            return result
        except (OperationalError, InterfaceError) as e:
            retries += 1
            if max_retries is not None and retries > max_retries:
                print(f"\n[DB ERROR] Maximum execution retries ({max_retries}) reached. Skipping operation batch.")
                raise e
            
            print(f"\n[DB TIMEOUT / DROPPED PORT] Database network fault caught: {e}")
            print(f"Retrying connection context in {backoff} seconds... (Attempt {retries})")
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)  # Caps max waiting limits to 60s
        except Exception as e:
            print(f"\n[CRITICAL ERROR] Non-transient execution failure (Query/Schema bug): {e}")
            raise e
        finally:
            if conn:
                conn.close()

def ensure_postgres_table(config):
    """Checks for the table design footprint and initializes it inside PostgreSQL if missing."""
    print("Checking database layout definitions...")
    
    def run_schema(conn):
        create_table_query = """
        CREATE TABLE IF NOT EXISTS user_profiles (
            user_id VARCHAR(50) PRIMARY KEY,
            full_name VARCHAR(255) NOT NULL,
            device_id UUID NOT NULL,
            home_region VARCHAR(10) NOT NULL,
            home_city VARCHAR(100) NOT NULL,
            home_state VARCHAR(100) NOT NULL,
            home_country VARCHAR(100) NOT NULL,
            associated_accounts TEXT[] NOT NULL,
            credit_cards TEXT[] NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            phone_number VARCHAR(50),
            ssn_or_tax_id VARCHAR(50),
            date_of_birth DATE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_user_profiles_region ON user_profiles(home_region);
        """
        with conn.cursor() as cur:
            cur.execute(create_table_query)
            conn.commit()
            print("PostgreSQL layout verified successfully (Table 'user_profiles' ready).")

    # This runs infinitely at startup (max_retries=None) until the database is live and reachable
    execute_db_with_retry(config, run_schema, max_retries=None)

def bulk_create_users(user_ids, config, update_memory_maps=True):
    """
    Generates and bulk-inserts multiple users into PostgreSQL in a single batch.
    Maps to local memory only if update_memory_maps is True.
    """
    db_records = []
    
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
        pii_dob = fake.date_of_birth(minimum_age=18, maximum_age=75).strftime('%Y-%m-%d')

        if update_memory_maps:
            USER_NAME_MAP[user_id] = full_name
            USER_ACCOUNT_MAP[user_id] = associated_accounts
            USER_DEVICE_MAP[user_id] = device_id
            USER_HOME_REGION[user_id] = home_region
            USER_HOME_LOCATION[user_id] = location

        db_records.append((
            user_id, full_name, device_id, home_region, location["city"],
            location["state"], location["country"], associated_accounts,
            credit_cards, pii_email, pii_phone, pii_ssn, pii_dob
        ))
    
    def run_insert(conn, records):
        with conn.cursor() as cur:
            insert_query = """
                INSERT INTO user_profiles (
                    user_id, full_name, device_id, home_region, home_city, home_state, home_country, 
                    associated_accounts, credit_cards, email, phone_number, ssn_or_tax_id, date_of_birth
                ) VALUES %s
                ON CONFLICT (user_id) DO NOTHING;
            """
            execute_values(cur, insert_query, records)
            conn.commit()
            print(f"Successfully batch-inserted {len(records)} users into Postgres.")

    try:
        # For initial baseline, block until success. For dynamic engine growth, use capped retries.
        retries_allowed = None if update_memory_maps else 4
        execute_db_with_retry(config, run_insert, db_records, max_retries=retries_allowed)
    except Exception:
        print("Warning: Dynamic worker could not store new profile iteration into database due to network exhaustion.")

def initialize_user_pool(pool_size, config):
    """Initializes the baseline minimum active user pool on startup using rapid bulk insertion."""
    user_pool = [f"user_{str(i).zfill(4)}" for i in range(1, pool_size + 1)]
    print(f"Initializing baseline transaction pool of {pool_size} users...")
    
    # Bulk insert the entire pool over a single connection session
    bulk_create_users(user_pool, config, update_memory_maps=True)
        
    print("Baseline active pool successfully built and saved to Postgres.")
    return user_pool

def get_transaction_location(user_id, is_anomaly):
    if is_anomaly:
        home_region = USER_HOME_REGION[user_id]
        alternate_regions = [r for r in REGIONS.keys() if r != home_region]
        target_region = random.choice(alternate_regions)
        return random.choice(REGIONS[target_region])
    else:
        return USER_HOME_LOCATION[user_id]

def ensure_kafka_topic(producer_config, topic_name):
    admin_client = AdminClient(producer_config)
    cluster_metadata = admin_client.list_topics(timeout=10)
    
    if topic_name not in cluster_metadata.topics:
        print(f"Topic '{topic_name}' not found. Creating it...")
        new_topic = NewTopic(topic=topic_name, num_partitions=6)
        fs = admin_client.create_topics([new_topic])
        for topic, future in fs.items():
            future.result()
    else:
        print(f"Topic '{topic_name}' ready.")

AVRO_SCHEMA_STR = """
{
  "type": "record",
  "name": "Payment",
  "namespace": "com.example.payments",
  "fields": [
    {"name": "transaction_id", "type": "string"},
    {"name": "user_id", "type": "string"},
    {"name": "user_name", "type": "string"},
    {"name": "device_id", "type": "string"},
    {"name": "payer_account_no", "type": "string"},
    {"name": "payee_account_no", "type": "string"},
    {"name": "category", "type": "string"},
    {"name": "payment_method", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string"},
    {"name": "timestamp", "type": "long"},
    {
      "name": "address",
      "type": {
        "type": "record",
        "name": "AddressRecord",
        "fields": [
          {"name": "city", "type": "string"},
          {"name": "state", "type": "string"},
          {"name": "country", "type": "string"}
        ]
      }
    }
  ]
}
"""

def main():
    config = configparser.ConfigParser()
    config.read('config.ini')

    target_tps = config.getint('simulation', 'target_tps')
    valid_percentage = config.getfloat('simulation', 'valid_transaction_percentage')
    user_pool_size = config.getint('simulation', 'user_pool_size')
    
    anomaly_threshold = valid_percentage / 100.0

    # Dynamic Table Pre-check (Includes retry loops)
    ensure_postgres_table(config)

    # Initialize Baseline Active transaction pool via Bulk Action
    user_pool = initialize_user_pool(user_pool_size, config)
    next_user_index = user_pool_size + 1

    schema_registry_client = SchemaRegistryClient(dict(config['schema_registry']))
    avro_serializer = AvroSerializer(schema_registry_client, AVRO_SCHEMA_STR)

    producer_config = dict(config['kafka'])
    topic_name = producer_config.pop('topic.name') 
    ensure_kafka_topic(producer_config, topic_name)

    producer_config['linger.ms'] = 10 
    producer = Producer(producer_config)

    print(f"Streaming data at {target_tps} TPS...")
    interval = 1.0 / target_tps
    
    last_user_addition_time = time.time()
    user_addition_interval = 60.0  # 1 minute

    try:
        while True:
            start_time = time.time()

            # --- DB-ONLY BACKGROUND GROWING ENGINE (1 user / minute) ---
            if start_time - last_user_addition_time >= user_addition_interval:
                new_user_id = f"user_{str(next_user_index).zfill(4)}"
                print(f"\n[DB Growth Only] Writing new registration directly to DB: {new_user_id}")
                
                # Wrapped in custom error tolerance behavior so streaming remains real-time
                bulk_create_users([new_user_id], config, update_memory_maps=False)
                
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

            payment_data = {
                "transaction_id": str(uuid.uuid4()),
                "user_id": payer_id,
                "user_name": user_name,
                "device_id": device_id,
                "payer_account_no": payer_account,
                "payee_account_no": payee_account,
                "category": category,
                "payment_method": payment_method,
                "amount": amount,
                "currency": "USD",
                "timestamp": int(time.time() * 1000),
                "address": {
                    "city": location["city"],
                    "state": location["state"],
                    "country": location["country"]
                }
            }

            ctx = SerializationContext(topic_name, MessageField.VALUE)
            producer.produce(
                topic=topic_name,
                key=payment_data["user_id"],
                value=avro_serializer(payment_data, ctx)
            )
            producer.poll(0)

            elapsed = time.time() - start_time
            sleep_time = interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\nStopping stream...")
    finally:
        producer.flush()

if __name__ == "__main__":
    main()