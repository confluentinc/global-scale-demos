# Shift-Left Pattern with Flink SQL and Confluent Cloud Workshop

This self-paced workshop demonstrates how to implement a shift-left pattern for improved data quality and governance in a brokerage scenario using **Apache Flink SQL** and **Confluent Cloud**.

## Workshop Objectives
- Understand the shift-left pattern and its benefits in data processing
- Learn to use Apache Flink SQL for real-time data processing
- Implement data quality checks and governance policies early in the data pipeline
- Perform stateless and stateful operations on streaming data
- Integrate with **Confluent Cloud** and **MongoDB**

## Prerequisites
- Basic knowledge of SQL
- Familiarity with stream processing concepts
- A **Confluent Cloud** account

## Workshop Structure
1. Introduction to the shift-left pattern and use case
2. Setting up the environment
3. Generating sample data
4. Filtering and cleaning data
5. Performing aggregations
6. Implementing joins
7. Sinking processed data

**Happy learning!**

## Introduction to Shift-Left Pattern and Use Case

The shift-left pattern in data processing involves moving data quality checks and governance policies earlier in the data pipeline. This approach helps to:
- Identify and address data quality issues early
- Reduce costs associated with downstream data cleanup
- Improve overall data reliability and trustworthiness

In our brokerage use case, we'll implement this pattern to process trade data more efficiently and accurately. We'll use **Apache Flink SQL** with **Confluent Cloud** to:
- Generate and ingest trade data
- Apply data quality filters
- Perform real-time aggregations
- Join streaming data with static data
- Sink processed data for further analysis

By the end of this workshop, you'll have a practical understanding of how to implement the shift-left pattern using **Flink SQL** and **Confluent Cloud**.


## Workshop Options

You can proceed with the workshop in the following ways:

1. **Run Terraform Scripts**  
   Utilize Terraform scripts to set up the necessary infrastructure.  
   [Access the instructions to run terraform scripts here](https://github.com/nidhi-ks/Flink-demo-for-Financial-Services/blob/main/Running%20Terraform%20Scripts.md).

2. **Use Confluent Cloud UI**  
   Set up your environment directly through the Confluent Cloud user interface.  
   [Access the instruction to setup from Confluent Cloud UI here](https://github.com/nidhi-ks/Flink-demo-for-Financial-Services/blob/main/FlinkSQL.md).

3. **Tableflow**

Confluent Tableflow simplifies getting your real-time Kafka topic data into open table formats like Apache Iceberg, stored in cloud object storage. It automatically handles schema evolution and data compaction, providing a "zero-ETL" path to create query-ready tables for your analytics engines.

* **Streamlined Data Lakehouse:** Easily transform Kafka topics into analytical tables.
* **Automated Maintenance:** Tableflow manages schema evolution and data compaction.
* **Open Formats:** Data is materialized as Apache Iceberg for broad compatibility.

[Get started: Enable Tableflow in this Lab](https://github.com/nidhi-ks/Flink-demo-for-Financial-Services/blob/main/tableflow%20lab.md)


[Integrate Tableflow with AWS Glue and Query in AWS Athena](https://github.com/nidhi-ks/Flink-demo-for-Financial-Services/blob/main/Integrate%20tableflow%20with%20aws%20glue%20and%20query%20with%20Athena.md)
   

Feel free to choose the method that best suits your preferences!


