locals {
  demo_resources_oltp = can(module.oltp[0]) ? format(
    "MySql Host = %s\nMySql Port = %s\nMySql User = %s\n\nS3 Bucket Name = %s\nS3 Bucket ARN  = %s\n\nConfluent Environment   = %s : %s\nConfluent Kafka Cluster = %s : %s\n\nTableflow REST Catalog Endpoint = \"%s\"",
    module.oltp[0].mysql_db_address,
    var.mysql_database_port,
    var.mysql_database_username,
    module.oltp[0].tableflow_s3_bucket,
    module.oltp[0].tableflow_s3_bucket_arn,
    module.oltp[0].env_name,
    module.oltp[0].env_id,
    module.oltp[0].kafka_name,
    module.oltp[0].kafka_id,
    module.oltp[0].confluent_rest_catalog_uri
  ) : "OLTP Resources are not deployed, If required set TF_VAR_enable_oltp=true"
}

output "demo_resources_oltp" {
  value = local.demo_resources_oltp
}

locals {
  demo_resources_olap_snowflake = can(module.olap_snowflake[0]) ? format(
<<-EOT
Snowflake External Volume  = %s
Snowflake Catalog Integration   = "%s-rest-catalog-integration"

Snowflake Warehouse = %s
Snowflake Database  = %s
Snowflake Schema    = public
Snowflake Table     = low_stock_alerts

Run this query on Snowflake UI once data is synced to S3 bucket via Tableflow:

CREATE OR REPLACE ICEBERG TABLE low_stock_alerts 
EXTERNAL_VOLUME = '"%s"'
CATALOG = '"%s-rest-catalog-integration"'
CATALOG_TABLE_NAME = 'low_stock_alerts';
EOT
,
    module.olap_snowflake[0].snowflake_external_volume_name,
    var.project_name,
    module.olap_snowflake[0].snowflake_warehouse_name,
    module.olap_snowflake[0].snowflake_database_name,
    module.olap_snowflake[0].snowflake_external_volume_name,
    var.project_name
  ) : "OLAP Snowflake Resources are not deployed, If required set TF_VAR_enable_olap_snowflake=true"
}

output "demo_resources_olap_snowflake" {
  value = local.demo_resources_olap_snowflake
}



locals {
  demo_resources_olap_glue = can(module.olap_glue[0]) ? format(
<<-EOT
Start Querying the data in Amazon Athena Trino SQL with below details:
Amazon Athena Database  = %s
Amazon Athena Query Result S3 Bucket   = %s
Amazon Athena Table = low_stock_alerts

Update Query result location to above s3 bucket.

Run this query on trino SQL:
select * from low_stock_alerts;
EOT
,
    module.oltp[0].kafka_id,
    module.oltp[0].tableflow_s3_bucket
  ) : "OLAP Glue Resources are not deployed, If required set TF_VAR_enable_olap_glue=true"
}

output "demo_resources_olap_glue" {
  value = local.demo_resources_olap_glue
}

