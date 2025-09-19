# --- Service Accounts ---
# Resource for 'custom-connect-manager' Service Account
resource "confluent_service_account" "custom_connect_manager_service_account" {
  display_name = "${var.project_name}-connect-manager" 
  description  = "Service account for managing custom connectors infrastructure in ${var.project_name}"
}

resource "confluent_service_account" "custom_connect_worker_service_account" {
  display_name = "${var.project_name}-connect-worker" 
  description  = "Service account for custom connector operations in ${var.project_name}"
}

resource "confluent_service_account" "custom_connect_statements_runner" {
  display_name = "${var.project_name}-connect-statements-runner" 
  description  = "Service account for running Flink Statements in '${var.project_name}' Kafka cluster"
}

resource "confluent_service_account" "custom_connect_app_manager" {
  display_name = "${var.project_name}-connect-app-manager" 
  description  = "Service account that has got full access to Flink resources in ${var.project_name} environment"
}

# --- Data Sources for Flink ---
data "confluent_flink_region" "flink_region" {
  cloud  = confluent_kafka_cluster.basic.cloud
  region = confluent_kafka_cluster.basic.region
}

# --- Role Bindings ---
# Role Binding for 'custom-connect-manager'
resource "confluent_role_binding" "app_manager_kafka_cluster_admin" {
  principal   = "User:${confluent_service_account.custom_connect_manager_service_account.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

# Schema Registry access for connectors
resource "confluent_role_binding" "connector_schema_registry_resource_owner" {
  principal   = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.advanced.resource_name}/subject=*"
}

# Flink Role Bindings
resource "confluent_role_binding" "custom_connect_statements_runner_environment_admin" {
  principal   = "User:${confluent_service_account.custom_connect_statements_runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = data.confluent_environment.existing_staging.resource_name
}

resource "confluent_role_binding" "custom_connect_app_manager_flink_developer" {
  principal   = "User:${confluent_service_account.custom_connect_app_manager.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = data.confluent_environment.existing_staging.resource_name
}

resource "confluent_role_binding" "custom_connect_app_manager_transaction_id_developer_read" {
  principal   = "User:${confluent_service_account.custom_connect_app_manager.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${confluent_kafka_cluster.basic.rbac_crn}/kafka=${confluent_kafka_cluster.basic.id}/transactional-id=_confluent-flink_*"
}

resource "confluent_role_binding" "custom_connect_app_manager_transaction_id_developer_write" {
  principal   = "User:${confluent_service_account.custom_connect_app_manager.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${confluent_kafka_cluster.basic.rbac_crn}/kafka=${confluent_kafka_cluster.basic.id}/transactional-id=_confluent-flink_*"
}

resource "confluent_role_binding" "custom_connect_app_manager_assigner" {
  principal   = "User:${confluent_service_account.custom_connect_app_manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.my_org.resource_name}/service-account=${confluent_service_account.custom_connect_statements_runner.id}"
}

# --- API Keys ---
# API Key for 'custom-connect-manager'
resource "confluent_api_key" "app_manager_kafka_api_key" {
  display_name = "${var.project_name}-app-manager-kafka-api-key"
  description  = "Kafka API Key owned by '${var.project_name}-connect-manager' service account"
  owner {
    id          = confluent_service_account.custom_connect_manager_service_account.id
    api_version = confluent_service_account.custom_connect_manager_service_account.api_version
    kind        = confluent_service_account.custom_connect_manager_service_account.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = data.confluent_environment.existing_staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app_manager_kafka_cluster_admin
  ]
}

# Schema Registry API Key for connectors
resource "confluent_api_key" "schema_registry_api_key" {
  display_name = "${var.project_name}-schema-registry-api-key"
  description  = "Schema Registry API Key for ${var.project_name} connectors"
  owner {
    id          = confluent_service_account.custom_connect_worker_service_account.id
    api_version = confluent_service_account.custom_connect_worker_service_account.api_version
    kind        = confluent_service_account.custom_connect_worker_service_account.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.advanced.id
    api_version = data.confluent_schema_registry_cluster.advanced.api_version
    kind        = data.confluent_schema_registry_cluster.advanced.kind

    environment {
      id = data.confluent_environment.existing_staging.id
    }
  }

  depends_on = [
    confluent_role_binding.connector_schema_registry_resource_owner
  ]
}

resource "confluent_api_key" "custom_connect_app_manager_flink_api_key" {
  display_name = "${var.project_name}-connect-app-manager-flink-api-key"
  description  = "Flink API Key that is owned by '${var.project_name}-connect-app-manager' service account"
  owner {
    id          = confluent_service_account.custom_connect_app_manager.id
    api_version = confluent_service_account.custom_connect_app_manager.api_version
    kind        = confluent_service_account.custom_connect_app_manager.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.flink_region.id
    api_version = data.confluent_flink_region.flink_region.api_version
    kind        = data.confluent_flink_region.flink_region.kind
    environment {
      id = data.confluent_environment.existing_staging.id
    }
  }

  depends_on = [
    confluent_role_binding.custom_connect_app_manager_flink_developer,
    confluent_role_binding.custom_connect_app_manager_transaction_id_developer_read,
    confluent_role_binding.custom_connect_app_manager_transaction_id_developer_write
  ]
}

# Service Account for DynamoDB Source Connector
resource "confluent_service_account" "dynamodb_source_service_account" {
  display_name = "${var.project_name}-dynamodb-source"
  description  = "Service account for DynamoDB CDC Source connector in ${var.project_name}"
}

# Role binding for DynamoDB connector
resource "confluent_role_binding" "dynamodb_connector_describe_on_cluster" {
  principal   = "User:${confluent_service_account.dynamodb_source_service_account.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

# API Key for DynamoDB connector
resource "confluent_api_key" "dynamodb_connector_api_key" {
  display_name = "${var.project_name}-dynamodb-connector-api-key"
  description  = "Kafka API Key for DynamoDB CDC Source connector in ${var.project_name}"
  owner {
    id          = confluent_service_account.dynamodb_source_service_account.id
    api_version = confluent_service_account.dynamodb_source_service_account.api_version
    kind        = confluent_service_account.dynamodb_source_service_account.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = data.confluent_environment.existing_staging.id
    }
  }

  depends_on = [
    confluent_role_binding.dynamodb_connector_describe_on_cluster,
    aws_dynamodb_table.user_personalization
  ]
}
