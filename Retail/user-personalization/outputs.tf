output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = aws_db_instance.postgresql.endpoint
}

output "postgres_port" {
  description = "PostgreSQL RDS port"
  value       = aws_db_instance.postgresql.port
}

output "postgres_database_name" {
  description = "PostgreSQL database name"
  value       = aws_db_instance.postgresql.db_name
}

output "postgres_username" {
  description = "PostgreSQL master username"
  value       = aws_db_instance.postgresql.username
  sensitive   = true
}

output "postgres_security_group_id" {
  description = "PostgreSQL Security Group ID"
  value       = aws_security_group.postgres_sg.id
}

output "postgres_kms_key_id" {
  description = "KMS key ID used for PostgreSQL encryption"
  value       = aws_kms_key.postgres_key.key_id
}

output "ssm_password_parameter_name" {
  description = "Name of the SSM Parameter Store SecureString holding the database password"
  value       = aws_ssm_parameter.rds_password_param.name
}

# --- Kafka Cluster Outputs ---
output "kafka_cluster_id" {
  description = "The ID of the Confluent Kafka Cluster."
  value       = confluent_kafka_cluster.basic.id
}

output "kafka_cluster_rest_endpoint" {
  description = "The REST Endpoint of the Confluent Kafka Cluster."
  value       = confluent_kafka_cluster.basic.rest_endpoint
}

# --- Service Account Outputs ---
output "custom_connect_manager_service_account_id" {
  description = "The ID of the 'custom-connect-manager' Service Account."
  value       = confluent_service_account.custom_connect_manager_service_account.id
}

output "custom_connect_worker_service_account_id" {
  description = "The ID of the 'custom-connect-worker' Service Account."
  value       = confluent_service_account.custom_connect_worker_service_account.id
}

output "custom_connect_statements_runner_service_account_id" {
  description = "The ID of the 'custom-connect-statements-runner' Service Account."
  value       = confluent_service_account.custom_connect_statements_runner.id
}

output "custom_connect_app_manager_service_account_id" {
  description = "The ID of the 'custom-connect-app-manager' Service Account."
  value       = confluent_service_account.custom_connect_app_manager.id
}

# --- API Key Outputs (IDs only, never secrets directly) ---
output "app_manager_kafka_api_key_id" {
  description = "The ID of the Kafka API Key for 'custom-connect-manager'."
  value       = confluent_api_key.app_manager_kafka_api_key.id
}

output "schema_registry_api_key_id" {
  description = "The ID of the Schema Registry API Key for connectors."
  value       = confluent_api_key.schema_registry_api_key.id
}

output "custom_connect_app_manager_flink_api_key_id" {
  description = "The ID of the Flink API Key for 'custom-connect-app-manager'."
  value       = confluent_api_key.custom_connect_app_manager_flink_api_key.id
}