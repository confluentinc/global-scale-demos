output "cc_compute_pool_name" {
  description = "Flink Compute Pool ID"
  value = confluent_flink_compute_pool.cc_flink_compute_pool.id
}

output "cc_hands_env" {
  description = "Confluent Cloud Environment ID"
  value       = confluent_environment.cc_handson_env.id 
}

output "cc_handson_sr" {
  description = "CC Schema Registry Region"
  value       = data.confluent_schema_registry_region.cc_handson_sr
}

output "cc_sr_cluster" {
  description = "CC SR Cluster ID"
  value       = confluent_schema_registry_cluster.cc_sr_cluster.id 
}

output "cc_kafka_cluster" {
  description = "CC Kafka Cluster ID"
  value       = confluent_kafka_cluster.cc_kafka_cluster.id 
}

# Updated connector outputs
output "datagen_users" {
  description = "CC Datagen Users Connector ID"
  value       = confluent_connector.datagen_users.id
}

output "datagen_trades_data" {
  description = "CC Datagen Trades Data Connector ID"
  value       = confluent_connector.datagen_trades_data.id
}

output "datagen_transaction_data" {
  description = "CC Datagen Transaction Data Connector ID"
  value       = confluent_connector.datagen_transaction_data.id
}

# New topic outputs (optional, but good for visibility)
output "users_data_topic_name" {
  description = "Users Data Topic Name"
  value       = confluent_kafka_topic.users_data.topic_name
}

output "trades_data_topic_name" {
  description = "Trades Data Topic Name"
  value       = confluent_kafka_topic.trades_data.topic_name
}

output "transaction_data_topic_name" {
  description = "Transaction Data Topic Name"
  value       = confluent_kafka_topic.transaction_data.topic_name
}


output "SRKey" {
  description = "CC SR Key"
  value       = confluent_api_key.sr_cluster_key.id
}
output "SRSecret" {
  description = "CC SR Secret"
  value       = confluent_api_key.sr_cluster_key.secret
  sensitive = true
}

output "AppManagerKey" {
  description = "CC AppManager Key"
  value       = confluent_api_key.app_manager_kafka_cluster_key.id
}
output "AppManagerSecret" {
  description = "CC AppManager Secret"
  value       = confluent_api_key.app_manager_kafka_cluster_key.secret
  sensitive = true
}

output "ClientKey" {
  description = "CC clients Key"
  value       = confluent_api_key.clients_kafka_cluster_key.id
}
output "ClientSecret" {
  description = "CC Client Secret"
  value       = confluent_api_key.clients_kafka_cluster_key.secret
  sensitive = true
}
