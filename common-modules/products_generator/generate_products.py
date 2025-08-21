import mysql.connector
from faker import Faker
import faker_commerce
import random
import time
import uuid
import os

# --- Database Configuration ---
# Get credentials from environment variables
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "your_username")
DB_PASSWORD = os.getenv("DB_PASSWORD", "your_password")
DB_NAME = os.getenv("DB_NAME", "your_database")
TABLE_NAME = "products"

def create_connection():
    """Create a database connection."""
    connection = None
    retry_count = 5
    while retry_count > 0 and not connection:
        try:
            print("Attempting to connect to the database...")
            connection = mysql.connector.connect(
                host=DB_HOST,
                user=DB_USER,
                password=DB_PASSWORD,
                database=DB_NAME,
                connect_timeout=10
            )
            if connection.is_connected():
                print("Successfully connected to the database.")
                return connection
        except mysql.connector.Error as e:
            print(f"Error connecting to MySQL: {e}")
            retry_count -= 1
            print(f"Retrying in 5 seconds... ({retry_count} retries left)")
            time.sleep(5)
    return None


def insert_product(connection, product_data):
    """Insert a new product into the products table."""
    cursor = connection.cursor()
    insert_query = f"""
    INSERT INTO {TABLE_NAME} (product_id, product_name, quantity)
    VALUES (%s, %s, %s)
    """
    try:
        cursor.execute(insert_query, product_data)
        connection.commit()
        print(f"Inserted: {product_data[1]}")
    except mysql.connector.Error as e:
        print(f"Error inserting data: {e}")
        connection.rollback()
    finally:
        cursor.close()

def main():
    """Main function to generate and push data continuously."""
    db_connection = create_connection()
    if not db_connection:
        print("Could not establish database connection. Exiting.")
        return

    # Initialize Faker and add the commerce provider
    fake = Faker()
    fake.add_provider(faker_commerce.Provider)

    try:
        while True:
            product_id = str(uuid.uuid4())
            product_name = fake.ecommerce_name()
            quantity = random.randint(1, 100)

            product_data = (product_id, product_name, quantity)
            insert_product(db_connection, product_data)

            # Adjust the sleep time to control the rate of insertion
            time.sleep(60)

    except KeyboardInterrupt:
        print("\nProcess stopped by user.")
    finally:
        if db_connection and db_connection.is_connected():
            db_connection.close()
            print("Database connection closed.")

if __name__ == "__main__":
    main()