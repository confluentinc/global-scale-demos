# Single service account owning Kafka, Schema Registry, and Flink resources for
# this project -- mirrors the sa-w5wrg9j ("metro-demo-flink") account that was
# created manually and granted EnvironmentAdmin, which was confirmed sufficient
# to run Flink SQL statements without any additional FlinkDeveloper/Assigner role.
resource "confluent_service_account" "app_manager" {
  display_name = "${var.project_name}-app-manager"
  description  = "Service account managing Kafka, Schema Registry and Flink resources for ${var.project_name}"
}

resource "confluent_role_binding" "app_manager_environment_admin" {
  principal   = "User:${confluent_service_account.app_manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.this.resource_name
}

resource "confluent_api_key" "app_manager_kafka_api_key" {
  display_name = "${var.project_name}-kafka-api-key"
  description  = "Kafka API key owned by ${var.project_name}-app-manager"

  owner {
    id          = confluent_service_account.app_manager.id
    api_version = confluent_service_account.app_manager.api_version
    kind        = confluent_service_account.app_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.this.id
    api_version = confluent_kafka_cluster.this.api_version
    kind        = confluent_kafka_cluster.this.kind

    environment {
      id = confluent_environment.this.id
    }
  }

  depends_on = [
    confluent_role_binding.app_manager_environment_admin
  ]
}

resource "confluent_api_key" "app_manager_sr_api_key" {
  display_name = "${var.project_name}-schema-registry-api-key"
  description  = "Schema Registry API key owned by ${var.project_name}-app-manager"

  owner {
    id          = confluent_service_account.app_manager.id
    api_version = confluent_service_account.app_manager.api_version
    kind        = confluent_service_account.app_manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.essentials.id
    api_version = data.confluent_schema_registry_cluster.essentials.api_version
    kind        = data.confluent_schema_registry_cluster.essentials.kind

    environment {
      id = confluent_environment.this.id
    }
  }

  depends_on = [
    confluent_role_binding.app_manager_environment_admin
  ]
}

resource "confluent_api_key" "app_manager_flink_api_key" {
  display_name = "${var.project_name}-flink-api-key"
  description  = "Flink API key owned by ${var.project_name}-app-manager"

  owner {
    id          = confluent_service_account.app_manager.id
    api_version = confluent_service_account.app_manager.api_version
    kind        = confluent_service_account.app_manager.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.this.id
    api_version = data.confluent_flink_region.this.api_version
    kind        = data.confluent_flink_region.this.kind

    environment {
      id = confluent_environment.this.id
    }
  }

  depends_on = [
    confluent_role_binding.app_manager_environment_admin
  ]
}
