locals {
  demo_resources_oltp = can(module.oltp[0]) ? format(
  <<-EOT
  

  Resources provisioned on AWS:
   1. RDS - MySql DB : host = %s , port = %s , user = %s
   2. S3 Bucket : %s for tableflow, S3 Bucket ARN  = %s
  
  Resources provisioned on Confluent:
   1. Confluent Environment   = %s : %s
   2. Confluent Kafka Cluster = %s : %s
   3. Mysql CDC Connector 
   4. Flink Queries
   5. Tableflow is enabled for topic: low_stock_alerts. if paused/failed resume it.
      Tableflow REST Catalog Endpoint = "%s" 


EOT
  , module.oltp[0].mysql_db_address,
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

output "a_demo_resources_oltp" {
  value = local.demo_resources_oltp
}




locals {
  demo_resources_olap_glue = can(module.olap_glue[0]) ? format(
<<-EOT


  AWS Glue and Athena Usage:
    1. Search Athena in AWS console
    2. Use Trino SQL
    3. Select database : %s
    4. Update Query result location to this s3 bucket : %s
    5. Start Querying your data:
      SELECT * FROM low_stock_alerts;


EOT
,
    module.oltp[0].kafka_id,
    module.oltp[0].tableflow_s3_bucket
  ) : "OLAP Glue Resources are not deployed, If required set TF_VAR_enable_olap_glue=true"
}

output "c_demo_resources_olap_glue" {
  value = local.demo_resources_olap_glue
}

locals {
  demo_resources_olap_databricks = can(module.olap_databricks[0]) ? format(
<<-EOT


Databricks requires to update AWS IAM Role Trust Policy with the role's own ARN for Assume Role.
  1. Visit AWS IAM Console
  2. Search for this role: %s
  3. Update trust policy for this role
  4. Remove "AWS": "%s" from Principal block.
  5. Add "AWS": ["%s","%s"] in Principal block.
  6. Find this bucket : %s in S3 console
  7. Visit subdirectory v1 and find a sub-dir which contains metadata , _delta_log and data for table low_stock_alerts
  8. Copy S3 URI for this directory and update <topic_s3_uri> in below query
  9. Open SQL Editor in Databricks console and choose catalog: %s and schema: demoschema
  10. Create same table in databricks with this query:
      CREATE TABLE low_stock_alerts
      USING DELTA 
      LOCATION '<topic_s3_uri>';
  11. Start Querying your data:
      SELECT * FROM low_stock_alerts;


EOT
,
    module.olap_databricks[0].databricks_s3_access_role_name ,
    module.olap_databricks[0].unity_catalog_role_arn,
    module.olap_databricks[0].unity_catalog_role_arn,
    module.olap_databricks[0].databricks_s3_access_role_arn,
    module.oltp[0].tableflow_s3_bucket,
    module.olap_databricks[0].unity_catalog_name
  ) : "OLAP Databricks Resources are not deployed, If required set TF_VAR_enable_olap_databricks=true"
}


output "d_demo_resources_olap_databricks" {
  value = local.demo_resources_olap_databricks
}






