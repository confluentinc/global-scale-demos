<div align="center">

# Real-Time Financial Intelligence on Confluent Cloud
### A Streaming, Flink SQL, CSFLE & Lakehouse Blueprint for BFSI

</div>

This blueprint provisions an end-to-end real-time financial intelligence platform
with **Terraform**. It stands up an AWS RDS PostgreSQL instance wired for Debezium
Change Data Capture (CDC), streams changes into **Confluent Cloud**, runs continuous
fraud and upsell analytics in **Apache Flink**, encrypts PII in flight with
Client-Side Field-Level Encryption (**CSFLE**), and continuously materializes live
ledger data into an Amazon S3 data lake as **Apache Iceberg** tables via **Tableflow**,
cataloged in AWS Glue.

Everything in this blueprint deploys with a single `terraform apply`.

### What You'll Build

1. **Real-time transaction ingestion** — a Dockerized Python generator streams
   simulated payment transactions into a Postgres OLTP database, which Debezium CDC
   captures and publishes as Avro events to Confluent Cloud.
2. **PII protection with CSFLE** — user profile updates tagged with PII fields (name,
   device ID, home address, linked accounts, card numbers) are automatically
   client-side encrypted against an AWS KMS key before they reach the broker; anything
   that fails encryption is routed to a `failed-encryption-records` dead-letter topic.
3. **Stream processing with Flink SQL** — three always-on statements over the
   `payments` topic:
   - `account_daily_ledger` — a 5-minute tumbling aggregation of credits, debits, net
     change, and transaction counts per account.
   - `fraudulent_alerts` — impossible-travel detection (country change in
     &lt;10 minutes), rapid device-switch detection (&lt;60 seconds between distinct
     devices), and statistical amount anomalies via the built-in `ML_DETECT_ANOMALIES`
     function.
   - `upsell_opportunities` — flags high-velocity accounts in real time and
     recommends a matching financial product (corporate card, managed portfolio,
     merchant services, etc.).
4. **Lakehouse sync (Tableflow)** — `account_daily_ledger` is continuously mirrored to
   an S3 bucket as Apache Iceberg tables, with metadata synced to AWS Glue Data
   Catalog for querying via Athena.
5. **AI tool context (RTCE / MCP)** — the deploy writes an `ibm-bob-mcp.json` file that
   registers Confluent's Real-Time Context Engine endpoint as a Model Context
   Protocol server, so MCP-compatible AI assistants can query the live streaming data.

## Architecture

![Architecture Diagram](terraform/assets/images/arc.png)

## Agenda

- [Prerequisites](#prerequisites)
- [Step 1: Deploy the stack](#step-1-deploy-the-stack)
- [Step 2: The data generator](#step-2-the-data-generator)
- [Step 3: PII governance with CSFLE](#step-3-pii-governance-with-csfle)
- [Step 4: The Flink SQL pipeline](#step-4-the-flink-sql-pipeline)
- [Step 5: Lakehouse sync with Tableflow](#step-5-lakehouse-sync-with-tableflow)
- [Step 6: AI tool context (RTCE / MCP)](#step-6-ai-tool-context-rtce--mcp)
- [Step 7: Clean up](#step-7-clean-up)
- [Repository structure](#repository-structure)
- [Further resources](#further-resources)

## Prerequisites

1. **A Confluent Cloud account.** [Sign up here](https://www.confluent.io/confluent-cloud/tryfree/)
   — new accounts include free credits that comfortably cover this blueprint.
2. **[Terraform](https://developer.hashicorp.com/terraform/install)**
3. **[Docker](https://docs.docker.com/get-docker/)**, running locally — required to
   build and run the Python transaction generator container.
4. **An AWS account** with permissions for IAM, RDS (Postgres), S3, KMS, and Glue Data
   Catalog.
5. **Confluent Cloud API keys** with Cloud Resource Manager administration scope.

> **Note:** This blueprint creates real billed resources in both Confluent Cloud and
> AWS. Run `terraform destroy` (see [Step 7](#step-7-clean-up)) when you're done to
> avoid ongoing charges.

## Step 1: Deploy the stack

```bash
git clone https://github.com/confluentinc/global-scale-demos.git
cd global-scale-demos/BFSI/financial-intelligence/terraform/
terraform init
```

Export your credentials and layout variables — none of these are committed to the
repo, so set them in your shell before applying:

```bash
# General Infrastructure Variables
export TF_VAR_project_name="financial-intelligence"
export TF_VAR_aws_region="ap-south-1"
export TF_VAR_hardware="Aarch64" # Switch to "x86_64" depending on your local machine

# Confluent Cloud Administration Keys
export TF_VAR_confluent_cloud_api_key="<YOUR_CONFLUENT_CLOUD_RESOURCE_API_KEY>"
export TF_VAR_confluent_cloud_api_secret="<YOUR_CONFLUENT_CLOUD_RESOURCE_API_SECRET>"

# AWS Pipeline Access Permissions
export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
export AWS_SESSION_TOKEN="<YOUR_AWS_SESSION_TOKEN>" # Leave blank if your IAM profile doesn't use temporary tokens
```

> **Tip:** Confirm your local Docker daemon is running before applying — Terraform
> needs direct Docker access to build the data generator image.

```bash
terraform plan   # review the resources and IAM permissions that will be created
terraform apply  # provision the end-to-end platform (~10-15 minutes)
```

Once it completes, check the terminal output for the deployed resource summary
(RDS endpoint, S3 bucket, Confluent environment/cluster IDs, and next steps).

## Step 2: The data generator

`terraform/assets/datagen/payments.py` is a Dockerized Python app that simulates a
pool of users transacting across regions (US, EU, APAC), payment methods (UPI, SWIFT,
card, wallet, net banking), and merchant categories. It writes user profile rows to
Postgres (captured by CDC) and streams payment transaction events directly to
Confluent Cloud, occasionally injecting the location/device patterns that the fraud
detection queries in Step 4 are designed to catch.

## Step 3: PII governance with CSFLE

The Debezium connector captures `user_profiles` table changes (name, device ID, home
address, linked accounts, card numbers) as Avro events tagged with a PII schema rule.
Confluent Cloud automatically routes tagged fields through **Client-Side Field-Level
Encryption**, encrypting them against a customer-managed AWS KMS key
(`confluent_schema_registry_kek.aws_kms_csfle_key`) before they ever leave the
producer. Payloads that fail encryption are redirected to a `failed-encryption-records`
dead-letter topic instead of being dropped silently.

## Step 4: The Flink SQL pipeline

Three Flink SQL statement pairs run continuously against the `payments` topic (see
`terraform/main.tf` for the full statements):

| Table | Logic |
|---|---|
| `account_daily_ledger` | 5-minute tumbling window per account: total received, total debited, net change, and credit/debit/combined transaction counts. |
| `fraudulent_alerts` | `MATCH_RECOGNIZE` patterns for impossible travel (country change &lt;10 min apart) and device switching (&lt;60 sec apart), plus `ML_DETECT_ANOMALIES` for statistical amount outliers (95% confidence, &gt;$1000). |
| `upsell_opportunities` | Classifies each account's 5-minute activity into a lead type (high debit volume/frequency, high credit volume, high-velocity merchant) and recommends a matching product with a priority tier. |

## Step 5: Lakehouse sync with Tableflow

`account_daily_ledger` is registered as a `confluent_tableflow_topic`, which
continuously materializes the windowed ledger stream into the `tableflow_byob_bucket`
S3 bucket as Apache Iceberg tables. Metadata is synced to AWS Glue Data Catalog via a
`confluent_catalog_integration`, so it's immediately queryable from Athena:

```sql
SELECT * FROM account_daily_ledger;
```

Set your Athena "Query result location" to `s3://<tableflow_byob_bucket>/query-results/`
before running queries.

## Step 6: AI tool context (RTCE / MCP)

A `confluent_rtce_topic` resource enables Confluent's Real-Time Context Engine on
`account_daily_ledger`, and a `local_file.ibm_bob_mcp` resource writes an
`ibm-bob-mcp.json` file into the `terraform/` folder. This file registers the RTCE
endpoint as a Model Context Protocol server, so MCP-compatible AI assistants (e.g.
IBM Bob) can query the live streaming ledger data directly.

## Step 7: Clean up

Because AWS KMS and Confluent Cloud resources are cross-bound, a couple of
dependency-tracked resources need to be released from Terraform's state before a
full teardown:

```bash
terraform destroy -auto-approve

# If the above errors out on KMS/provider-integration dependencies, run:
terraform state rm confluent_schema_registry_kek.aws_kms_csfle_key confluent_provider_integration.main
terraform destroy -auto-approve
```

## Repository structure

| Path | What it is |
|---|---|
| `terraform/main.tf` | Core infrastructure: RDS, KMS, Confluent environment/cluster, CDC connector, Flink statements, Tableflow, Glue, RTCE. |
| `terraform/variables.tf` / `outputs.tf` | Input variables and post-apply resource summaries. |
| `terraform/iam_role_module/` | Reusable IAM role module for AWS-side permissions. |
| `terraform/assets/datagen/` | The transaction generator app: `payments.py`, `Dockerfile`, `requirements.txt`. |
| `terraform/assets/schemas/` | Avro key/value schemas for the `user_profiles` CDC topic. |
| `terraform/assets/images/` | Architecture diagram. |

## Further resources

- [Confluent Cloud for Apache Flink](https://docs.confluent.io/cloud/current/flink/index.html)
- [Client-Side Field Level Encryption](https://docs.confluent.io/cloud/current/security/encrypt/csfle/overview.html)
- [Tableflow](https://docs.confluent.io/cloud/current/topics/tableflow/overview.html)
- [Built-in AI/ML Functions (`ML_DETECT_ANOMALIES`)](https://docs.confluent.io/cloud/current/ai/builtin-functions/overview.html)
- [Terraform Provider for Confluent](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
