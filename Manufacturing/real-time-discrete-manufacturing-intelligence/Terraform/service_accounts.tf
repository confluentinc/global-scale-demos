resource "confluent_service_account" "connect_sa" {
  display_name = "${var.name_prefix}-connect-sa"
  description  = "Service account for fully-managed connectors"
}

resource "confluent_api_key" "kafka_admin" {
  display_name = "${var.name_prefix}-kafka-admin-key"

  owner {
    id          = confluent_service_account.connect_sa.id
    api_version = confluent_service_account.connect_sa.api_version
    kind        = confluent_service_account.connect_sa.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind
    environment {
      id = data.confluent_environment.target.id
    }
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_service_account" "flink_sa" {
  display_name = "${var.name_prefix}-flink-sa"
  description  = "Service account for Flink statements"
}

resource "confluent_api_key" "flink_api" {
  display_name = "${var.name_prefix}-flink-api-key"

  owner {
    id          = confluent_service_account.flink_sa.id
    api_version = confluent_service_account.flink_sa.api_version
    kind        = confluent_service_account.flink_sa.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.region.id
    api_version = data.confluent_flink_region.region.api_version
    kind        = data.confluent_flink_region.region.kind
    environment {
      id = data.confluent_environment.target.id
    }
  }

  depends_on = [
    confluent_flink_compute_pool.pool,
    confluent_role_binding.flink_sa_developer,
    confluent_role_binding.flink_sa_flink_admin,
    confluent_role_binding.flink_assigner
  ]
}

# resource "confluent_api_key" "sr_api" {
#   display_name = "sr-api-key"
#   description  = "Schema Registry API key"
#
#   owner {
#     id          = confluent_service_account.connect_sa.id
#     api_version = "iam/v2"
#     kind        = "ServiceAccount"
#   }
#
#   managed_resource {
#     id          = data.confluent_schema_registry_cluster.env.id
#     api_version = data.confluent_schema_registry_cluster.env.api_version
#     kind        = data.confluent_schema_registry_cluster.env.kind
#     environment { id = data.confluent_environment.target.id }
#   }
#
#   depends_on = [
#     confluent_role_binding.connect_sa_data_steward
#   ]
# }