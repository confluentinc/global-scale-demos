# Output success message
output "tables_created" {
  value = "Tables created successfully in database ${var.postgres_db_name}"
  depends_on = [null_resource.create_tables]
}

output "flink_catalog"  { value = data.confluent_environment.target.display_name }
output "flink_database" { value = confluent_kafka_cluster.main.display_name }
output "kafka_cluster_id" { value = confluent_kafka_cluster.main.id }

output "sr_crn" {
  value = data.confluent_schema_registry_cluster.env.resource_name
}