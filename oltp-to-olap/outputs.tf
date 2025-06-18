output "demo_resources" {
  value = <<-EOT

       MySql Host =  ${aws_db_instance.mysql_db.address}
       MySql Port =  ${aws_db_instance.mysql_db.port}
       MySql User =  ${aws_db_instance.mysql_db.username}
       
       S3 Bucket Name = ${aws_s3_bucket.tableflow_byob_bucket.bucket}
       S3 Bucket ARN  = ${aws_s3_bucket.tableflow_byob_bucket.arn}
       
       Snowflake S3 Access Role Name = ${aws_iam_role.snowflake_s3_access_role.name}
       Snowflake S3 Access Role ARN  = ${aws_iam_role.snowflake_s3_access_role.arn}

       Confluent Environment   =  ${confluent_environment.confluent_project_env.display_name} : ${confluent_environment.confluent_project_env.id}
       Confluent Kafka Cluster =  ${confluent_kafka_cluster.basic.display_name} : ${confluent_kafka_cluster.basic.id}
       
       Tableflow REST Catalog Endpoint =  "https://tableflow.${var.aws_region}.aws.confluent.cloud/iceberg/catalog/organizations/${data.confluent_organization.main.id}/environments/${confluent_environment.confluent_project_env.id}"
       
  EOT
}




# output "external_volume_external_id" {
#   value = jsondecode(snowflake_external_volume.tableflow_s3.describe_output[1].value).STORAGE_AWS_EXTERNAL_ID
# }

# output "external_volume_user_arn" {
#   value = jsondecode(snowflake_external_volume.tableflow_s3.describe_output[1].value).STORAGE_AWS_IAM_USER_ARN
# }
