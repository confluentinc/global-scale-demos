locals {
  demo_resources_oltp = format(
    <<-EOT


  Resources provisioned on AWS:
   1. RDS - Postgres DB : host = %s , port = %s , user = %s
   2. S3 Bucket : %s for tableflow, S3 Bucket ARN  = %s
   
  Resources provisioned on Confluent:
   1. Confluent Environment   = %s
   2. Confluent Kafka Cluster = %s : %s
   3. Postgres CDC Source Connector 
   4. Flink Queries (Account Daily Ledger, Fraudulent Alerts, Upsell Opportunities)
   5. Tableflow is enabled for topic: account_daily_ledger. If paused/failed resume it.
   6. Real Time Context Engine is enabled for topic: account_daily_ledger. You can use ibm-bob-mcp.json generated file in IBM Bob MCP Settings for quering the data.


EOT
    ,
    aws_db_instance.postgres_db.address,
    var.postgres_database_port,
    var.postgres_database_username,
    aws_s3_bucket.tableflow_byob_bucket.bucket,
    aws_s3_bucket.tableflow_byob_bucket.arn,
    confluent_environment.confluent_project_env.display_name,
    confluent_kafka_cluster.basic.display_name,
    confluent_kafka_cluster.basic.id
  )
}

output "a_demo_resources_oltp" {
  value       = local.demo_resources_oltp
  description = "Summary of deployed OLTP and streaming ingestion infrastructure components."
}

locals {
  demo_resources_olap_glue = format(
    <<-EOT


  AWS Glue and Athena Usage:
    1. Search "Athena" in the AWS Management Console.
    2. Ensure your data parsing uses the structured Trino query interface.
    3. Select your automatically synchronized database instance target ID: %s
    4. Update your Athena "Query result location" settings to point to this S3 bucket: s3://%s/query-results/
    5. Start querying your live, structured streaming financial snapshots directly:
       SELECT * FROM account_daily_ledger;

EOT
    ,
    confluent_kafka_cluster.basic.id,
    aws_s3_bucket.tableflow_byob_bucket.bucket
  )
}

output "c_demo_resources_olap_glue" {
  value       = local.demo_resources_olap_glue
  description = "Instructions and links for executing analytical workflows using AWS Glue and Athena."
}

output "e_ibm_bob_mcp_config" {
  value       = "Local AI context config file written to: ${local_file.ibm_bob_mcp.filename}"
  description = "Status of the Model Context Protocol (MCP) server context mappings."
}