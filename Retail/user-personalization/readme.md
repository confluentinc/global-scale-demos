# AWS & Confluent Cloud Data Pipeline: CDC, Flink Processing, and PostgreSQL Sink

This project deploys a robust, real-time data pipeline using **Terraform** to provision infrastructure on **Amazon Web Services (AWS)** and **Confluent Cloud**.

The pipeline is designed to capture **Change Data Capture (CDC)** streams from both a transactional database (**PostgreSQL**) and an event-driven database (**DynamoDB**), process the data in real-time using **Confluent Flink**, and then sink the derived analytical results back into a PostgreSQL database for reporting and application use.

---

## 🚀 Key Technologies

| Technology | Role |
| :--- | :--- |
| **Terraform** | Infrastructure as Code (IaC) for provisioning all resources. |
| **AWS RDS (PostgreSQL)** | Source and Sink transactional database (CDC enabled). |
| **AWS DynamoDB** | Event-driven data source (Streams enabled for CDC). |
| **Confluent Cloud** | Managed Kafka, Schema Registry, and Flink for data transport and processing. |
| **Kafka Connect** | Used for the PostgreSQL CDC Source, DynamoDB CDC Source, and PostgreSQL Sink. |
| **Confluent Flink** | Real-time stream processing for complex transformations and aggregations. |

---

## 🎯 Architecture Summary

The data pipeline has three primary stages:

1.  **Data Ingestion (CDC):**
    * **PostgreSQL CDC Source:** Captures table changes (users, items, reviews) for enrichment and real-time updates.
    * **DynamoDB CDC Source:** Captures user interaction events (purchases, clicks, views) from the `dev-user-personalization` table.
2.  **Stream Processing (Confluent Flink):**
    * Multiple Flink SQL tables are defined to perform real-time joins, aggregations, and windowed analyses on the incoming streams.
    * Processing creates derived datasets like `co_purchase_counts`, `user_purchase_totals`, and `purchase_windowed_counts`.
3.  **Data Sink:**
    * A **PostgreSQL Sink Connector** writes all the processed, enriched data from Flink back into the PostgreSQL database, making the derived insights immediately available for application consumption.



---

## 💻 Deployment and Configuration

The project is managed by several Terraform configuration files:

### 1. Core AWS Infrastructure (`aws.tf`)

This file provisions the foundational AWS resources:

* **PostgreSQL RDS Instance:** Provisioned with `engine_version 17.5`. Crucially, the `rds.logical_replication` parameter is set to **1** to enable PostgreSQL's CDC features.
* **DynamoDB Table (`dev-user-personalization`):** Configured with **PAY\_PER\_REQUEST** billing and a composite key (`user_id` HASH, `timestamp` RANGE). **DynamoDB Streams** are enabled with the `NEW_IMAGE` view type to serve as the CDC source.
* **IAM & Security:** Includes an IAM role for Enhanced Monitoring and a security group (`postgres-sg`) to control access.

### 2. Data Generation (`python-executer.tf`)

This section uses Terraform's `null_resource` to execute Python scripts that prepare the environment for testing:

* `run_postgres_prerequisites_script`: Creates initial tables in PostgreSQL (users, categories, items, reviews) and populates them with sample data.
* `run_dynamodb_prerequisites_script`: Inserts a large volume of simulated user interaction events (purchases, clicks, views) into the DynamoDB table.

### 3. Confluent Cloud Setup (`confluent_accounts_keys.tf`, `confluentcluster.tf`)

This defines the necessary Confluent Cloud components:

* **Service Accounts & API Keys:** Dedicated service accounts (`dynamodb_source_service_account`, `custom_connect_manager_service_account`, etc.) are created and bound to specific roles (e.g., `CloudClusterAdmin`, `FlinkDeveloper`). API keys are generated for each to facilitate secure authentication.
* **Kafka Cluster:** A `SINGLE_ZONE` availability cluster is deployed in the configured cloud and region.

### 4. Connectors and Access Control (`confluent_conectors.tf`, `acls.tf`)

This configures the Kafka Connect ecosystem:

| Connector Name | Type | Key Features |
| :--- | :--- | :--- |
| `postgre-sql-cdc-source` | `PostgresCdcSourceV2` | Captures changes from PostgreSQL. Output format is **AVRO**. |
| `dynamodb_cdc_source` | `DynamoDbCdcSource` | Captures changes from DynamoDB Streams. Applies a **transform** to extract the `after` field (new item state). Output format is **AVRO**. |
| `postgres_sink_all_flink_tables` | `PostgresSink` | Writes Flink output topics back to PostgreSQL. Enables `auto.create` and `auto.evolve` for schema flexibility. |

**ACLs:** The `acls.tf` file ensures all service accounts have the minimum required permissions (e.g., `READ` on sink topics, `WRITE` on source topics).

### 5. Flink Stream Processing (`flink.tf`)

The Flink setup defines a series of connected tables for real-time analytics:

| Flink Table/Stream | Purpose & Analysis | Source Connector |
| :--- | :--- | :--- |
| `interaction_data` | Primary user behavior stream (purchases, clicks, views). | DynamoDB CDC |
| `co_purchase_counts` | **Product Recommendation:** Counts co-purchased items for "frequently bought together" suggestions. | Flink Processing |
| `user_purchase_totals` | **User Segmentation:** Joins user details (PostgreSQL) with purchase counts to create user profiles. | Flink Processing |
| `highly_rated_item_details` | **Featured Products:** Joins review, item, and category data to identify top-rated items. | Flink Processing |
| `item_shared_by_user_pair` | **Collaborative Filtering:** Counts items shared between two users to identify similar interests. | Flink Processing |
| `purchase_windowed_counts` | **Fraud/Pattern Detection:** Analyzes multiple purchases of the same item within a 30-minute window. | Flink Processing |

---

## 🛠️ Getting Started (Prerequisites)

To deploy this project, you will need:

1.  **Terraform CLI** installed.
2.  **AWS Account** configured with appropriate credentials (via environment variables, profiles, or a credentials file).
3.  **Confluent Cloud Account** and relevant API keys for the provider configuration.
4.  **Python 3** and required libraries (e.g., `psycopg2`, `boto3`) to run the data generation scripts.

### Configuration

Set the required environment variables for the AWS and Confluent Cloud providers. **Note:** These credentials should be managed securely, such as through a secret manager or encrypted variable files, not hardcoded.

```bash
export TF_VAR_project_name="test"  #add a unique identifier
# AWS Credentials (used by Terraform and the DynamoDB Connector)
export TF_VAR_access_key="XXXXXXXXXXX"
export TF_VAR_secret_key="XXXXXXXXXXXXXX"
export TF_VAR_db_password="XXXXXXXXXXXXXX"  #add a password for database

# Confluent Cloud API Keys (for the Confluent Terraform Provider)
export TF_VAR_confluent_cloud_api_key="XXXXXXXXXX"
export TF_VAR_confluent_cloud_api_secret="XXXXXXXXXXX" 

```
### Deployment

To provision the infrastructure and deploy the entire data pipeline, run the following Terraform commands:

```bash

# Initialize Terraform:
terraform init

# Review the plan (optional but highly recommended):

terraform plan

#Apply the configuration to deploy the infrastructure:

terraform apply

```
