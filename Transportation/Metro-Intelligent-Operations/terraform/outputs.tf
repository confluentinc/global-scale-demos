output "environment_id" {
  value = confluent_environment.this.id
}

output "kafka_cluster_id" {
  value = confluent_kafka_cluster.this.id
}

output "kafka_bootstrap_endpoint" {
  value = confluent_kafka_cluster.this.bootstrap_endpoint
}

output "kafka_rest_endpoint" {
  value = confluent_kafka_cluster.this.rest_endpoint
}

output "schema_registry_rest_endpoint" {
  value = data.confluent_schema_registry_cluster.essentials.rest_endpoint
}

output "flink_compute_pool_id" {
  value = confluent_flink_compute_pool.this.id
}

output "app_manager_service_account_id" {
  value = confluent_service_account.app_manager.id
}

output "kafka_api_key" {
  value     = confluent_api_key.app_manager_kafka_api_key.id
  sensitive = true
}

output "kafka_api_secret" {
  value     = confluent_api_key.app_manager_kafka_api_key.secret
  sensitive = true
}

output "schema_registry_api_key" {
  value     = confluent_api_key.app_manager_sr_api_key.id
  sensitive = true
}

output "schema_registry_api_secret" {
  value     = confluent_api_key.app_manager_sr_api_key.secret
  sensitive = true
}

output "generated_env_file" {
  value = local_sensitive_file.producer_env.filename
}

output "live_map_url" {
  description = "Open this in a browser once apply finishes."
  value       = "http://localhost:${var.live_map_port}"
}

output "producer_container_name" {
  value = var.run_producer_container ? docker_container.producer[0].name : null
}

output "live_map_container_name" {
  value = docker_container.live_map.name
}

output "surge_detection_enabled" {
  value = var.enable_surge_detection
}
