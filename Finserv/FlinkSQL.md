# Workshop Instructions

## 1. Create a free account
Sign up for Confluent Cloud at [Confluent Cloud - Try Free](https://www.confluent.io/confluent-cloud/tryfree/).

---

## 2. Create a new environment
- After logging in, click on **'Add new environment'**.
- Give it a meaningful name (e.g., `<your-name>-environment`).
- Select the **Essentials** package for Stream Governance.

---

## 3. Set up a new cluster
- Click on **'Add cluster'** and select a **Basic Cluster** for the workshop.
- Choose your preferred **cloud provider** and **region**, then click **Launch**.
- Your Confluent Cloud Kafka cluster is now up and running!

---

Alternatively , we have terraform scripts to automate the steps , please refer to `cflt-cloud.tf` for the cloud configuration

---

## 4. Creating a Datagen Connector to Pull Data in Confluent Cloud

### Create a new topic:
- Navigate to the **Topics** tab and click **Create New Topic**.
- Name the topic `trades_data`.

### Create another topic:
- Navigate to the **Topics** tab and click **Create New Topic**.
- Name the topic `users_data`.

---

Alternatively , we have terraform scripts to automate the steps , please refer to `topics.tf` for the creating topics

---


### Add a sample data connector:
- Go to the **Connectors** tab, click **Add Connector**, and search for the **Sample Data** connector.
- Select `Stock trades` as the **target topic**.
- Set **Output Message Format** to **Avro**.

### Configure the connector:
- In the **Advanced Configuration** section, choose **Trades** as the dataset.
- Leave the other settings as default and start the connector provisioning.
- Verify data ingestion into the `trades_data` topic.

### Advantages of using Avro Schema :

Avro, when used with Confluent, provides compact binary serialization and supports schema evolution, ensuring compatibility across streaming data. Its integration with Confluent’s Schema Registry allows for easy management of schemas, enhancing data consistency. Additionally, Avro’s language-agnostic nature facilitates seamless integration with various applications in the Confluent ecosystem.

---

### Add another sample data connector:
- Go to the **Connectors** tab, click **Add Connector**, and search for the **Sample Data** connector.
- Select `users_data` as the target topic 
- set **Output Message Format** to **Avro**.

### Configure the connector:
- In the **Advanced Configuration** section, choose **Users** as the dataset.
- Start the connector provisioning and verify data ingestion into the `users_data` topic.

---

Alternatively , we have terraform scripts to automate the steps , please refer to `cflt-connectors.tf` for the setting up datagen connectors

---


## 5. Creating a Compute Pool in Flink

### Navigate to the Flink tab:
- Hover over the **Flink** tab and click **Create Compute Pool**.

### Configure the compute pool:
- Ensure the region matches your Kafka cluster's region.
- Choose your preferred **cloud provider** and **region**.
- Leave the **Max CFU** setting as default.
- Provide a meaningful name for your compute pool.
- Your compute pool will be up and running in a few minutes.

---

Alternatively , we have terraform scripts to automate the steps , please refer to `flink.tf` for the spinning up a flink compute pool

---

## 6. Creating Tables in Flink

### 1. View the `trades_data` table:

Run the following command to view the table structure:

```sql
SHOW CREATE TABLE trades_data;
```
Shows the DDL statement for the table 

Output : 

```sql
CREATE TABLE `trades_data` (
  `key` VARBINARY(2147483647),
  `side` VARCHAR(2147483647) NOT NULL COMMENT 'A simulated trade side (buy or sell or short)',
  `quantity` INT NOT NULL COMMENT 'A simulated random quantity of the trade',
  `symbol` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated stock symbols',
  `price` INT NOT NULL COMMENT 'A simulated random trade price in pennies',
  `account` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated accounts assigned to the trade',
  `userid` VARCHAR(2147483647) NOT NULL COMMENT 'The simulated user who executed the trade'
) DISTRIBUTED BY HASH(`key`) INTO 3 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'connector' = 'confluent',
  'kafka.cleanup-policy' = 'delete',
  'kafka.max-message-size' = '2097164 bytes',
  'kafka.retention.size' = '0 bytes',
  'kafka.retention.time' = '7 d',
  'key.format' = 'raw',
  'scan.bounded.mode' = 'unbounded',
  'scan.startup.mode' = 'earliest-offset',
  'value.format' = 'avro-registry'
);
```

### 2. Adding Data to `trades_topic`

```sql
CREATE TABLE `trades_topic` (
  `key` VARBINARY(2147483647),
  `side` VARCHAR(2147483647) NOT NULL COMMENT 'A simulated trade side (buy or sell or short)',
  `quantity` INT NOT NULL COMMENT 'A simulated random quantity of the trade',
  `symbol` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated stock symbols',
  `price` INT NOT NULL COMMENT 'A simulated random trade price in pennies',
  `account` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated accounts assigned to the trade',
  `userid` VARCHAR(2147483647) NOT NULL COMMENT 'The simulated user who executed the trade'
);
```
Creates a table trades_topic

```sql
INSERT INTO trades_topic
SELECT * 
FROM trades_data;
```
Inserts data into trades_topic table from trades_data table 

## Filtering in Flink: Price and Quantity Greater Than 0


### 3. Creating the `filtered_trades` Table

```sql
CREATE TABLE `filtered_trades` (
  `key` VARBINARY(2147483647),
  `side` VARCHAR(2147483647) NOT NULL COMMENT 'A simulated trade side (buy or sell or short)',
  `quantity` INT NOT NULL COMMENT 'A simulated random quantity of the trade',
  `symbol` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated stock symbols',
  `price` INT NOT NULL COMMENT 'A simulated random trade price in pennies',
  `account` VARCHAR(2147483647) NOT NULL COMMENT 'Simulated accounts assigned to the trade',
  `userid` VARCHAR(2147483647) NOT NULL COMMENT 'The simulated user who executed the trade'
);
```
Creates table filteres_trades

```sql
Copy code
INSERT INTO `filtered_trades`
SELECT * 
FROM trades_topic
WHERE quantity > 0 
  AND price > 0 
  AND (side = 'BUY' OR side = 'SELL');
```
Inserts data into filtered_trades after filtering data based on conditions from trades_topic 

### 4. Joining `trades_topic` and `users_data` Using an Inner Join

```sql
SELECT /*+ STATE_TTL('t'='6h', 'u'='2h') */
    t.side,
    t.quantity,
    t.symbol,
    t.price,
    t.account,
    t.userid,
    u.registertime,
    u.regionid,
    u.gender
FROM 
    trades_topic t
INNER JOIN 
    users_data u 
ON 
    t.userid = u.userid;
```

The SQL statement retrieves data by performing an inner join between two tables: trades_topic (aliased as t) and users_data (aliased as u). It selects specific columns from both tables where the userid in trades_topic matches the userid in users_data, allowing you to combine trade details with user information such as registration time, region, and gender.

### 5. Running Aggregates and Window Functions

```sql
CREATE TABLE broker_trade_volume (
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3),
  userid STRING,
  total_number_of_shares BIGINT,
  total_amount_traded BIGINT
);
```

Creates a table broker_trade_volume 

```sql
INSERT INTO broker_trade_volume
SELECT 
    window_start, 
    window_end, 
    userid, 
    SUM(quantity) AS `total_number_of_shares`, 
    SUM(price) AS `total_amount_traded`
FROM TABLE (
    TUMBLE(TABLE filtered_trades, DESCRIPTOR($rowtime), INTERVAL '10' MINUTES)
)
GROUP BY 
    userid, 
    window_start, 
    window_end;
```
This SQL statement inserts aggregated trade data into the broker_trade_volume table. It selects the window_start, window_end, userid, and computes the total number of shares and total amount traded over 10-minute time windows, grouping the results by userid and the defined time windows

## 7. Creating Tables with Primary Keys and Ingesting Data

In Flink, when defining a primary key for a Kafka-backed table, the primary key columns typically need to appear at the beginning of the table schema (after any implicit Kafka `key` column). This ensures proper data distribution and enables `UPSERT` semantics if desired.

### 7.1 `users_data_with_pk` Table

This table is designed to hold user information with `userid` as the primary key.

```sql
CREATE TABLE `users_data_with_pk` (
    `userid` VARCHAR(2147483647) NOT NULL,
    `registertime` BIGINT NOT NULL,
    `regionid` VARCHAR(2147483647) NOT NULL,
    `gender` VARCHAR(2147483647) NOT NULL,
    PRIMARY KEY (`userid`) NOT ENFORCED
);
```
```sql
INSERT INTO users_data_with_pk
SELECT userid, registertime, regionid, gender
FROM `nks-prod-2d34603e`.`cluster_1`.`users_data`;
```

Explanation: This SQL statement continuously inserts data from the existing users_data table (which is likely an append-only stream) into the new users_data_with_pk table. If users_data_with_pk is configured as an upsert sink, this INSERT statement will produce records that, based on the userid primary key, will either insert new users or update existing user information if the userid already exists.

### 7.2 `transaction_data_with_pk` Table

This table is designed to hold user information with `userid` as the primary key.


```sql
CREATE TABLE `transaction_data_with_pk` (
    `transaction_id` BIGINT NOT NULL, 
    `card_id` BIGINT NOT NULL,
    `user_id` VARCHAR(2147483647) NOT NULL,
    `purchase_id` BIGINT NOT NULL,
    `store_id` INT NOT NULL,
    PRIMARY KEY (`transaction_id`) NOT ENFORCED 
);
```
```sql
insert into transaction_data_with_pk select `transaction_id` , 
  `card_id` ,
  `user_id` ,
  `purchase_id` ,
  `store_id` from `transaction_data`;
```
Explanation: This SQL statement creates transaction_data_with_pk with transaction_id as the primary key. Similar to users_data_with_pk, it's configured for upsert mode and transaction_id is used as the Kafka message key. The DISTRIBUTED BY HASH clause ensures that records with the same transaction_id are routed to the same partition, which is crucial for correct upsert semantics.

## 8. Watermark Definition

Watermarks are essential for proper event-time processing in Flink. They indicate the completeness of data up to a certain point in time, allowing Flink to correctly process late-arriving data and perform time-windowed aggregations and joins. The `$rowtime` pseudo-column represents the event time derived from the Kafka message timestamp.

```sql
ALTER TABLE `users_data_with_pk` MODIFY WATERMARK FOR `$rowtime` AS `$rowtime`;
```
```sql
ALTER TABLE `transaction_data_with_pk` MODIFY WATERMARK FOR `$rowtime` AS `$rowtime`;
```

## 8. Temporal Join: Enriching Transactions with User Data

Temporal joins allow you to join a stream with a versioned table (like a dimension table that changes over time) based on the event time of the stream. This is crucial for retrieving the "state" of a dimension at the precise moment a fact event occurred.

```sql
SELECT
    td.transaction_id,
    td.user_id,
    td.purchase_id,
    td.`$rowtime` AS transaction_event_time,
    ud.regionid AS user_region_at_transaction_time,
    ud.gender AS user_gender_at_transaction_time
FROM
    `transaction_data_with_pk` AS td
INNER JOIN
    `users_data_with_pk` FOR SYSTEM_TIME AS OF td.`$rowtime` AS ud
ON
    td.user_id = ud.userid;
```
Explanation: This query performs an event-time temporal join. For each transaction in transaction_data_with_pk (the left stream), it looks up the users_data_with_pk table (the right, versioned table) to find the user's regionid and gender as they were at the exact $rowtime of that particular transaction. 

## 8. Pattern Matching: Detecting Suspicious Transaction Sequences

MATCH_RECOGNIZE is a powerful Flink SQL feature for Complex Event Processing (CEP). It allows you to define patterns of events within a single stream and detect occurrences of these patterns. This is highly valuable for fraud detection, operational monitoring, and business analytics.

### 8.1 Simple Price Movement (Increase) within a Symbol

Detect if the price of a stock increases in two consecutive trades within a short interval, regardless of the user.

```sql
SELECT *
FROM `nks-prod-2d34603e`.`cluster_1`.`trades_data`
MATCH_RECOGNIZE (
    PARTITION BY symbol 
    ORDER BY `$rowtime`
    MEASURES
        A.symbol AS initial_symbol, 
        A.price AS initial_price,
        A.`$rowtime` AS initial_time,
        B.symbol AS higher_symbol,  
        B.price AS higher_price,
        B.`$rowtime` AS higher_time
    PATTERN (A B)
    DEFINE
        A AS TRUE, -- Any trade can be the start
        B AS B.price > A.price AND B.`$rowtime` < A.`$rowtime` + INTERVAL '30' SECOND -
) AS T;
```
### 8.2 Consecutive Buys or Sells by the Same User

Detect if a user makes two consecutive 'BUY' orders or two consecutive 'SELL' orders for any symbol within a short period. This can indicate aggressive trading behavior.

Pattern: Buy1 followed by Buy2 OR Sell1 followed by Sell2 by the same userid.

```sql
SELECT *
FROM `nks-prod-2d34603e`.`cluster_1`.`trades_data`
MATCH_RECOGNIZE (
    PARTITION BY userid 
    ORDER BY `$rowtime`
    MEASURES
        A.symbol AS symbol1,  
        A.side AS side1,
        A.quantity AS qty1,
        A.`$rowtime` AS time1,
        B.symbol AS symbol2,  
        B.side AS side2,
        B.quantity AS qty2,
        B.`$rowtime` AS time2
    PATTERN (A B)
    DEFINE
        A AS TRUE, 
        B AS (B.side = A.side) AND B.`$rowtime` < A.`$rowtime` + INTERVAL '1' MINUTE 
) AS T;
```

Explanation: This query will find instances where a single user places two buy orders or two sell orders (regardless of symbol or quantity) within a minute. This is a broader pattern more likely to match with limited sample data.


## 7. Pushing Data into MongoDB via Mongo Atlas Sink Connector

For demonstration purposes, we have selected MongoDB Atlas as the data sink. However, you can choose from any of the fully managed connectors available in Confluent.

### Setting Up MongoDB Atlas Sink Connector

1. Navigate to the Connectors tab.
2. Select **MongoDB Atlas Sink** Connector.
3. Choose the **broker_trade_volume** topic.
4. Provide authentication details (hostname, username, password, database, collection name).
5. Validate the connection to MongoDB Atlas.
6. Verify data ingestion in MongoDB Atlas.

### MongoDB Atlas Sink Connector Configuration

```sql
{
  "config": {
    "connector.class": "MongoDbAtlasSink",
    "name": "MongoDbAtlasSinkConnector_1",
    "schema.context.name": "default",
    "input.data.format": "AVRO",
    "cdc.handler": "None",
    "value.subject.name.strategy": "TopicNameStrategy",
    "delete.on.null.values": "false",
    "max.batch.size": "0",
    "bulk.write.ordered": "true",
    "rate.limiting.timeout": "0",
    "rate.limiting.every.n": "0",
    "write.strategy": "DefaultWriteModelStrategy",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "MNQKPKTJSJUAX3DH",
    "kafka.api.secret": "****************************************************************",
    "topics": "broker_trade_volume",
    "connection.host": "cflt-test.5afyk.mongodb.net",
    "connection.user": "test-cflt",
    "connection.password": "*********",
    "database": "trade-data",
    "collection": "trades_data_volume",
    "doc.id.strategy": "BsonOidStrategy",
    "doc.id.strategy.overwrite.existing": "false",
    "document.id.strategy.uuid.format": "string",
    "key.projection.type": "none",
    "value.projection.type": "none",
    "namespace.mapper.class": "DefaultNamespaceMapper",
    "server.api.deprecation.errors": "false",
    "server.api.strict": "false",
    "max.num.retries": "3",
    "retries.defer.timeout": "5000",
    "timeseries.timefield.auto.convert": "false",
    "timeseries.timefield.auto.convert.date.format": "yyyy-MM-dd[['T'][ ]][HH:mm:ss[[.][SSSSSS][SSS]][ ]VV[ ]'['VV']'][HH:mm:ss[[.][SSSSSS][SSS]][ ]X][HH:mm:ss[[.][SSSSSS][SSS]]]",
    "timeseries.timefield.auto.convert.locale.language.tag": "en",
    "timeseries.expire.after.seconds": "0",
    "ts.granularity": "None",
    "max.poll.interval.ms": "300000",
    "max.poll.records": "500",
    "tasks.max": "1"
  }
}

```

Please note that the user should have read write access on the database , collection specified in the connector . The data flows from Confluent Cloud to Mongo Atlas trades_data_volume collection . 
Verify the data inside the Mongo Atlas UI . 





