# Writes an .env file matching python-producer.py's expected variables, populated
# with this deployment's real endpoints/credentials. Copy or symlink it to
# ../.env if you want the producer to point at these Terraform-managed resources.
resource "local_sensitive_file" "producer_env" {
  filename = "${path.module}/generated.env"
  content  = <<-EOT
    BOOTSTRAP_SERVER=${trimprefix(confluent_kafka_cluster.this.bootstrap_endpoint, "SASL_SSL://")}
    KAFKA_API_KEY=${confluent_api_key.app_manager_kafka_api_key.id}
    KAFKA_API_SECRET=${confluent_api_key.app_manager_kafka_api_key.secret}
    TOPIC=${confluent_kafka_topic.camera_events.topic_name}

    SCHEMA_REGISTRY_URL=${data.confluent_schema_registry_cluster.essentials.rest_endpoint}
    SCHEMA_REGISTRY_API_KEY=${confluent_api_key.app_manager_sr_api_key.id}
    SCHEMA_REGISTRY_API_SECRET=${confluent_api_key.app_manager_sr_api_key.secret}

    TRAIN_HEADWAY_SECONDS=600
    TIME_SCALE=1.0
  EOT
}
