create database source;
use source;
CREATE TABLE customers (
  customer_id VARCHAR(255) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255),
  last_name VARCHAR(255),
  id_type VARCHAR(100),
  id_number VARCHAR(100)
);

INSERT INTO customers (customer_id, first_name, last_name, id_type, id_number)
VALUES ('c001', 'Alice', 'Smith', 'passport', 'P12345678');

INSERT INTO customers (customer_id, first_name, last_name, id_type, id_number)
VALUES ('c002', 'Bob', 'Johnson', 'driver_license', 'D98765432');

CREATE TABLE products (
  product_id VARCHAR(255) NOT NULL PRIMARY KEY,
  product_name VARCHAR(255),
  quantity INTEGER
);
