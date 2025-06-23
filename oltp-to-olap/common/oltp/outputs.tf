output "tableflow_reader_api_key_id" {
  value = confluent_api_key.app-reader-tableflow-api-key.id
}

output "tableflow_reader_api_key_secret" {
  value = confluent_api_key.app-reader-tableflow-api-key.secret
}

output "tableflow_admin_api_key_id" {
  value = confluent_api_key.app-manager-tableflow-api-key.id
}

output "tableflow_admin_api_key_secret" {
  value = confluent_api_key.app-manager-tableflow-api-key.secret
}

output "app_manager_user_id" {
  value = confluent_service_account.app-manager.id
}


output "env_id" {
    value = confluent_environment.confluent_project_env.id
}
output "env_name" {
    value = confluent_environment.confluent_project_env.display_name
}

output "env_resource_name" {
    value = confluent_environment.confluent_project_env.resource_name
}

output "kafka_id" {
    value = confluent_kafka_cluster.basic.id
}
output "kafka_name" {
    value = confluent_kafka_cluster.basic.display_name
}
output "confluent_rest_catalog_uri" {
    value = "https://tableflow.${var.aws_region}.aws.confluent.cloud/iceberg/catalog/organizations/${data.confluent_organization.main.id}/environments/${confluent_environment.confluent_project_env.id}"
}

output "tableflow_s3_bucket" {
   value = "${aws_s3_bucket.tableflow_byob_bucket.bucket}"
}

output "tableflow_s3_bucket_arn" {
   value = "${aws_s3_bucket.tableflow_byob_bucket.arn}"
}

output "mysql_db_address" {
    value = aws_db_instance.mysql_db.address
}
