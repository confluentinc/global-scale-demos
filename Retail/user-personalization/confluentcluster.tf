provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# --- Data Sources ---
# Reusing the existing staging environment.
data "confluent_environment" "existing_staging" {
  id = var.confluent_environment_id
}

data "confluent_schema_registry_cluster" "advanced" {
  environment {
    id = data.confluent_environment.existing_staging.id
  }
}

# Data source for organization ID (required for Flink Statement)
data "confluent_organization" "my_org" {}

# --- Locals ---
locals {
  database_server_name = "${var.project_name}-postgres"
}

# --- Kafka Cluster ---
resource "confluent_kafka_cluster" "basic" {
  display_name = "${var.project_name}-${var.kafka_cluster_display_name}"
  availability = "SINGLE_ZONE"
  cloud        = var.kafka_cluster_cloud
  region       = var.kafka_cluster_region
  standard {}  
  
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  
  lifecycle {
    prevent_destroy = false
  }
}
