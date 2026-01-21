This project provides a comprehensive, end-to-end demonstration of a real-time data streaming pipeline for the manufacturing industry. Leveraging **Confluent Cloud**, **Apache Flink**, and **PostgreSQL** on AWS, it showcases how raw sensor data is transformed into actionable manufacturing KPIs like **Production Yield**, **Defect Rates**, and **First Pass Yield (FPY)** in real-time.

---

## **Project Architecture**

The architecture follows a modern data-in-motion pattern to bridge the gap between the factory floor and executive decision-making.

1. **Data Generation:** A Dockerized Python script simulates a high-speed production line, injecting sensor data (temperature, pressure, quality status) into an **AWS RDS PostgreSQL** database.


2. **Ingestion (CDC):** Confluent’s **Postgres CDC Source Connector** captures every change in the database and streams it into Kafka topics.


3. **Real-Time Processing:** **Apache Flink** performs continuous SQL queries to enrich raw sensor events with Work Order metadata and compute granular KPIs over windowed streams.


4. **Egress (Sink):** Processed insights are streamed back to PostgreSQL using **Postgres Sink Connectors** in both `INSERT` and `UPSERT` modes for historical and real-time reporting.


5. **Visualization:** A live **Shopfloor Dashboard** (Dockerized) connects to the database to provide a real-time "command center" view of production health.



---

## **Technical Components**

### **Infrastructure & Security**

* **Terraform:** Automates the deployment of AWS VPCs, RDS instances, and the entire Confluent Cloud environment (Environments, Clusters, and Flink Compute Pools).


* **Service Accounts:** Uses dedicated accounts (`connect_sa`, `flink_sa`) with least-privilege RBAC roles such as `FlinkDeveloper` and `CloudClusterAdmin`.


* **Networking:** Configures a secure AWS environment with specific security groups and RDS parameter groups to enable logical replication for CDC.



### **Data Schema**

The project uses two primary tables to simulate the manufacturing context:

* **`work_orders`:** Metadata defining what is being produced, including product categories, codes, and planned quantities.
* **`sensor_events`:** The high-velocity stream including `item_id`, `line_number`, `routing_stage`, and Boolean quality indicators (`is_defective`).

### **Flink SQL KPIs**

Flink processes two primary streams of insight:

1. **Current Production Metrics:** Aggregates data by Work Order and Line to calculate live `yield_percent`, `defect_rate`, and average environmental factors (temperature/pressure).


2. **Production History:** Uses window functions (`RANGE BETWEEN UNBOUNDED PRECEDING`) to maintain a running historical count of quality metrics per unit as they pass through various stages.



---

## **Getting Started**

### **Prerequisites**

* Terraform (v1.5+)
* Docker and Docker Compose
* Confluent Cloud Account (API Keys required)
* AWS Account (IAM credentials for RDS deployment)

### **Deployment Steps**

1. **Initialize Infrastructure:**
```bash
terraform init
terraform apply

```


2. **Postgres Initialization:** The deployment automatically uses a `null_resource` and a tools container to execute `postgres-initial.sql` on the RDS instance.


3. **Launch Dashboard:** Once the connectors and Flink statements are active, access the dashboard locally at `http://localhost:8050`.



---

## **Key Manufacturing Insights Demonstrated**

**Real-Time Traceability:** Follow a specific `item_id` through every `routing_stage`.

**Bottleneck Detection:** Monitor `avg_pressure` and `avg_temperature` to predict failures before they occur.

**Performance Monitoring:** Compare `actual_produced` against `planned_quantity` for every active Work Order.

