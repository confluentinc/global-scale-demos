# -------------------------------------------------------
# Confluent Cloud Environment
# -------------------------------------------------------
resource "confluent_environment" "cc_handson_env" {
  display_name = "${var.use_prefix}${var.cc_env_name}-${random_id.id.hex}"
  lifecycle {
    prevent_destroy = false
  }
}

# --------------------------------------------------------
# Schema Registry
# --------------------------------------------------------
data "confluent_schema_registry_region" "cc_handson_sr" {
  cloud   = var.sr_cloud_provider
  region  = var.sr_cloud_region
  package = var.sr_package
}
resource "confluent_schema_registry_cluster" "cc_sr_cluster" {
  package = data.confluent_schema_registry_region.cc_handson_sr.package
  environment {
    id = confluent_environment.cc_handson_env.id
  }
  region {
    id = data.confluent_schema_registry_region.cc_handson_sr.id
  }
  lifecycle {
    prevent_destroy = false
  }
}

# --------------------------------------------------------
# Confluent Cloud Kafka Cluster
# --------------------------------------------------------
resource "confluent_kafka_cluster" "cc_kafka_cluster" {
  display_name = "${var.use_prefix}${var.cc_cluster_name}"
  availability = var.cc_availability
  cloud        = var.cc_cloud_provider
  region       = var.cc_cloud_region
  basic {}
  environment {
    id = confluent_environment.cc_handson_env.id
  }
  lifecycle {
    prevent_destroy = false
  }
}