import boto3
from faker import Faker
import random
import uuid
from datetime import datetime, timedelta
import sys

# --- Configuration ---
DDB_TABLE_NAME = f"{sys.argv[4]}-dev-user-personalization"
NUM_USERS = 100
NUM_ITEMS = 50
NUM_INTERACTIONS = 100

fake = Faker()

def get_dynamodb_resource():
    """Establishes a connection to DynamoDB using credentials from command line."""
    try:
        dynamodb = boto3.resource(
            'dynamodb',
            aws_access_key_id=sys.argv[1],
            aws_secret_access_key=sys.argv[2],
            region_name=sys.argv[3]
        )
        print(f"Successfully connected to DynamoDB in region {sys.argv[3]}.")
        return dynamodb
    except Exception as e:
        print(f"Error connecting to DynamoDB: {e}")
        raise

def get_existing_table(dynamodb):
    """Gets reference to existing DynamoDB table."""
    try:
        table = dynamodb.Table(DDB_TABLE_NAME)
        table.load()
        print(f"Successfully connected to existing table '{DDB_TABLE_NAME}'.")
        return table
    except Exception as e:
        print(f"Error accessing table '{DDB_TABLE_NAME}': {e}")
        raise

def insert_interactions_into_dynamodb(table):
    """Generates and inserts random interaction data using batch operations."""
    user_ids = list(range(1, NUM_USERS + 1))
    item_ids = list(range(1, NUM_ITEMS + 1))
    action_types = ['purchase', 'click', 'view']
    
    print(f"Generating {NUM_INTERACTIONS} interactions...")
    
    # Generate all interaction data first
    interactions = []
    start_date = datetime.now() - timedelta(days=365)
    
    for i in range(NUM_INTERACTIONS):
        user_id = random.choice(user_ids)
        timestamp_dt = fake.date_time_between(start_date=start_date, end_date="now")
        timestamp_for_dynamodb = str(int(timestamp_dt.timestamp()))
        action_type = random.choice(action_types)
        item_id = random.choice(item_ids) if random.random() < 0.9 else None

        interaction_data = {
            'user_id': str(user_id),
            'timestamp': timestamp_for_dynamodb,
            'activity_type': action_type,
            'action_type': action_type,
            'session_id': str(uuid.uuid4()),
            'device_type': random.choice(['mobile', 'desktop', 'tablet']),
            'browser_type': random.choice(['Chrome', 'Firefox', 'Safari', 'Edge']),
            'current_page_url': fake.url(),
            'ttl': int((datetime.now() + timedelta(days=365)).timestamp())
        }
        
        # Add optional fields
        if random.random() < 0.5:
            interaction_data['referrer_url'] = fake.url()
        
        if item_id is not None:
            interaction_data['item_id'] = str(item_id)
            
        interactions.append(interaction_data)
    
    print(f"Inserting {len(interactions)} interactions using batch operations...")
    
    # Insert in batches of 25 (DynamoDB batch_write_item limit)
    batch_size = 25
    total_inserted = 0
    
    for i in range(0, len(interactions), batch_size):
        batch = interactions[i:i + batch_size]
        
        # Prepare batch write request
        with table.batch_writer() as batch_writer:
            for item in batch:
                batch_writer.put_item(Item=item)
        
        total_inserted += len(batch)
        print(f"✓ Inserted batch {(i // batch_size) + 1}: {total_inserted}/{len(interactions)} interactions")
    
    print(f"Finished inserting {total_inserted} interactions using batch operations.")

def main():
    """Main function to orchestrate data insertion."""
    print("--- Starting DynamoDB Data Insertion ---")
    
    dynamodb_resource = get_dynamodb_resource()
    table = get_existing_table(dynamodb_resource)
    insert_interactions_into_dynamodb(table)
    
    print("--- Script completed successfully ---")

if __name__ == "__main__":
    main()