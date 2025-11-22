    -- Work Orders Table (Metadata)
    CREATE TABLE IF NOT EXISTS work_orders (
        workorder_id VARCHAR(50) PRIMARY KEY,
        product_category VARCHAR(50),
        product_code VARCHAR(50),
        planned_quantity INT,
        start_date TIMESTAMP,
        end_date TIMESTAMP
    );

    -- Sensor Events Table (Streaming Data)
    CREATE TABLE IF NOT EXISTS sensor_events (
        event_id SERIAL PRIMARY KEY,
        workorder_id VARCHAR(50) REFERENCES work_orders(workorder_id),
        item_id VARCHAR(50),           -- Unique ID for every unit produced
        batch_number VARCHAR(50),
        line_number VARCHAR(50),       -- e.g., LINE-1, LINE-2
        routing_stage VARCHAR(50),     -- e.g., Assembly, Painting
        temperature FLOAT,
        pressure FLOAT,
        is_defective BOOLEAN,          -- TRUE/FALSE instead of status codes
        defect_reason VARCHAR(100),    -- e.g., "Thermal Issue"
        operator_id VARCHAR(20),
        sensor_timestamp TIMESTAMP
    );
    -- Insert a dummy work order so we don't violate FK constraints
        INSERT INTO work_orders (workorder_id, product_category, product_code, planned_quantity, start_date, end_date)
        VALUES ('INIT-000', 'Initialization', 'INIT-CODE', 10, NOW(), NOW())
        ON CONFLICT (workorder_id) DO NOTHING;

        -- Insert 2 dummy events: 1 OK, 1 Defective
        -- This ensures the connector sees ALL columns and registers the schema correctly
        INSERT INTO sensor_events (workorder_id, item_id, batch_number, line_number, routing_stage, temperature, pressure, is_defective, defect_reason, operator_id, sensor_timestamp)
        VALUES
        ('INIT-000', 'INIT-ITEM-1', 'BATCH-000', 'LINE-1', 'Assembly', 80.0, 120.0, false, NULL, 'OP-INIT', NOW()),
        ('INIT-000', 'INIT-ITEM-2', 'BATCH-000', 'LINE-1', 'Assembly', 115.0, 120.0, true, 'Thermal Issue', 'OP-INIT', NOW());