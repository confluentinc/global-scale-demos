import psycopg2
from faker import Faker
import random
from datetime import datetime, timedelta
import sys

# --- Database Configuration ---
DB_CONFIG = {
        "host": sys.argv[1],
        "port": int(sys.argv[2]), 
        "database": sys.argv[3],
        "user": sys.argv[4],
        "password": sys.argv[5]

}
print(DB_CONFIG)

# Basic validation for database configuration
if not all(DB_CONFIG[key] for key in ["host", "database", "user", "password"]):
    print("Error: Database connection configuration (host, database, user, password) must be set.")
    exit(1)

# --- Data Generation Configuration ---
NUM_USERS = 100
NUM_ITEMS = 50
NUM_INTERACTIONS = 1000
NUM_REVIEWS = 200

# Define the schema name where tables will be created
SCHEMA_NAME = '"user_data"' 
# Initialize Faker for generating dummy data
fake = Faker()

def connect_db():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        raise

def create_tables(cur):
    """
    Creates the specified schema if it doesn't exist,
    then creates only the requested tables within that schema.
    """
    print(f"Ensuring schema {SCHEMA_NAME} exists...")
    cur.execute(f"CREATE SCHEMA IF NOT EXISTS {SCHEMA_NAME};")
    print(f"Schema {SCHEMA_NAME} ensured.")

    print(f"Creating tables in schema {SCHEMA_NAME} (without foreign key references)...")

    # USERS Table
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.users (
            user_id INTEGER PRIMARY KEY,
            username VARCHAR(50) UNIQUE NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            registration_date TIMESTAMP NOT NULL,
            last_login TIMESTAMP,
            first_name VARCHAR(50),
            last_name VARCHAR(50),
            date_of_birth DATE,
            gender VARCHAR(10),
            location VARCHAR(100),
            preferred_language VARCHAR(10),
            time_zone VARCHAR(50),
            account_status VARCHAR(20) DEFAULT 'active'
        );
    """)

    # CATEGORIES Table
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.categories (
            category_id SERIAL PRIMARY KEY,
            category_name VARCHAR(100) UNIQUE NOT NULL,
            parent_category_id INTEGER
        );
    """)

    # ITEMS Table
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.items (
            item_id INTEGER PRIMARY KEY,
            item_name VARCHAR(255) NOT NULL,
            description TEXT,
            category_id INTEGER,
            price NUMERIC(10, 2),
            availability_status VARCHAR(20) DEFAULT 'in_stock',
            image_url VARCHAR(255),
            release_date DATE,
            average_rating NUMERIC(3, 2) DEFAULT 0.00,
            number_of_ratings INTEGER DEFAULT 0,
            author_id INTEGER,
            brand_id INTEGER,
            creation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_updated_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)

    # REVIEWS Table
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.reviews (
            review_id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            rating_score INTEGER CHECK (rating_score >= 1 AND rating_score <= 5) NOT NULL,
            review_text TEXT,
            review_date TIMESTAMP NOT NULL,
            UNIQUE (user_id, item_id)
        );
    """)
    
    print("Tables created successfully: users, categories, items, interactions, reviews.")

def insert_data(cur, conn):
    """Inserts random data into the specified tables."""
    # Set the search_path for the current session to ensure inserts go into the correct schema
    cur.execute(f"SET search_path TO {SCHEMA_NAME}, public;")

    print("Inserting data...")

    # --- Insert CATEGORIES ---
    all_categories_definitions = [
        ("Electronics", None),
        ("Books", None),
        ("Clothing", None),
        ("Home & Kitchen", None),
        ("Sports & Outdoors", None),
        ("Laptops", "Electronics"),
        ("Smartphones", "Electronics"),
        ("Fiction", "Books"),
        ("Non-Fiction", "Books"),
        ("Men's Apparel", "Clothing"),
        ("Women's Apparel", "Clothing")
    ]

    category_name_to_id = {}
    category_ids = []

    print("Inserting categories...")
    inserted_count = 0
    while inserted_count < len(all_categories_definitions):
        initial_inserted_count = inserted_count
        for cat_name, parent_name in all_categories_definitions:
            if cat_name not in category_name_to_id:
                if parent_name is None:
                    cur.execute(f"INSERT INTO {SCHEMA_NAME}.categories (category_name, parent_category_id) VALUES (%s, %s) RETURNING category_id;", (cat_name, None))
                    new_id = cur.fetchone()[0]
                    category_name_to_id[cat_name] = new_id
                    category_ids.append(new_id)
                    inserted_count += 1
                elif parent_name in category_name_to_id:
                    parent_id = category_name_to_id[parent_name]
                    cur.execute(f"INSERT INTO {SCHEMA_NAME}.categories (category_name, parent_category_id) VALUES (%s, %s) RETURNING category_id;", (cat_name, parent_id))
                    new_id = cur.fetchone()[0]
                    category_name_to_id[cat_name] = new_id
                    category_ids.append(new_id)
                    inserted_count += 1

        if inserted_count == initial_inserted_count and inserted_count < len(all_categories_definitions):
            print("Error: Could not insert all categories due to potential missing parents or circular dependencies. Check category definitions.")
            break

    conn.commit()
    print(f"Inserted {len(category_ids)} categories.")


    # --- Insert USERS using a fixed integer range for user_id ---
    user_ids = list(range(1, NUM_USERS + 1))
    users_data_for_insert = []
    for i in user_ids:
        first_name = fake.first_name()
        last_name = fake.last_name()
        username = fake.unique.user_name()
        email = fake.unique.email()
        password_hash = fake.sha256()
        reg_date = fake.date_time_between(start_date="-2y", end_date="now")
        last_login = fake.date_time_between(start_date=reg_date, end_date="now")
        dob = fake.date_of_birth(minimum_age=18, maximum_age=80)
        gender = random.choice(['Male', 'Female', 'Other'])
        location = fake.city()
        lang = random.choice(['en', 'es', 'fr'])
        tz = random.choice(['UTC', 'America/New_York', 'Europe/London'])
        status = random.choice(['active', 'inactive'])
        # Prepend the generated user_id to the data tuple
        users_data_for_insert.append((i, username, email, password_hash, reg_date, last_login, first_name, last_name, dob, gender, location, lang, tz, status))

    print(f"Inserting {len(users_data_for_insert)} users with IDs from 1 to {NUM_USERS}...")
    cur.executemany(f"""
        INSERT INTO {SCHEMA_NAME}.users (user_id, username, email, password_hash, registration_date, last_login, first_name, last_name, date_of_birth, gender, location, preferred_language, time_zone, account_status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
    """, users_data_for_insert)
    conn.commit()
    print(f"Inserted {len(user_ids)} users.")

    # --- Insert ITEMS using a fixed integer range for item_id ---
    item_ids = list(range(1, NUM_ITEMS + 1))
    items_data_for_insert = []
    for i in item_ids:
        item_name = fake.catch_phrase()
        description = fake.paragraph(nb_sentences=3)
        category_id = random.choice(category_ids)
        price = round(random.uniform(5.00, 1000.00), 2)
        status = random.choice(['in_stock', 'out_of_stock', 'preorder'])
        image_url = fake.image_url()
        release_date = fake.date_between(start_date="-1y", end_date="today")
        # Prepend the generated item_id to the data tuple
        items_data_for_insert.append((i, item_name, description, category_id, price, status, image_url, release_date))

    print(f"Inserting {len(items_data_for_insert)} items with IDs from 1 to {NUM_ITEMS}...")
    cur.executemany(f"""
        INSERT INTO {SCHEMA_NAME}.items (item_id, item_name, description, category_id, price, availability_status, image_url, release_date)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
    """, items_data_for_insert)
    conn.commit()
    print(f"Inserted {len(item_ids)} items.")

    

    # --- Insert REVIEWS ---
    reviews_data = []
    for _ in range(NUM_REVIEWS):
        user_id = random.choice(user_ids)
        item_id = random.choice(item_ids)
        rating_score = random.randint(1, 5)
        review_text = fake.paragraph(nb_sentences=2) if random.random() < 0.8 else None
        review_date = fake.date_time_between(start_date="-6m", end_date="now")
        reviews_data.append((user_id, item_id, rating_score, review_text, review_date))

    cur.executemany(f"""
        INSERT INTO {SCHEMA_NAME}.reviews (user_id, item_id, rating_score, review_text, review_date)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (user_id, item_id) DO UPDATE SET
            rating_score = EXCLUDED.rating_score,
            review_text = EXCLUDED.review_text,
            review_date = EXCLUDED.review_date;
    """, reviews_data)
    conn.commit()
    print(f"Inserted/Updated {len(reviews_data)} reviews (some might be updates).")

    # --- Update average_rating in ITEMS based on new reviews ---
    cur.execute(f"""
        UPDATE {SCHEMA_NAME}.items i
        SET
            average_rating = sub.avg_rating,
            number_of_ratings = sub.num_ratings
        FROM (
            SELECT
                item_id,
                AVG(rating_score)::NUMERIC(3, 2) AS avg_rating,
                COUNT(rating_score) AS num_ratings
            FROM
                {SCHEMA_NAME}.reviews
            GROUP BY
                item_id
        ) AS sub
        WHERE i.item_id = sub.item_id;
    """)
    conn.commit()
    print("Updated item average ratings.")

    print("All data inserted successfully!")

def main():
    print("Working...")
    conn = None
    try:
        conn = connect_db()
        cur = conn.cursor()

        create_tables(cur)
        insert_data(cur, conn)

    except psycopg2.Error as e:
        print(f"Database operation failed: {e}")
        if conn:
            conn.rollback()
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        if conn:
            conn.rollback()
    finally:
        if conn:
            cur.close()
            conn.close()
            print("Database connection closed.")

if __name__ == "__main__":
    main()
