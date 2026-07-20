resource "confluent_flink_compute_pool" "this" {
  display_name = "${var.project_name}-flink-pool"
  cloud        = var.cloud
  region       = var.region
  max_cfu      = var.flink_max_cfu

  environment {
    id = confluent_environment.this.id
  }

  depends_on = [
    confluent_role_binding.app_manager_environment_admin,
    confluent_api_key.app_manager_flink_api_key,
  ]
}

# Sums headcount across all 8 coaches of a single train's departure event
# (1-minute tumbling window). See ../flink-sql/02_train_departure_totals.sql.
resource "confluent_flink_statement" "train_departure_totals" {
  statement = file("${path.module}/../flink-sql/02_train_departure_totals.sql")

  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.this.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.this.id
  }
  principal {
    id = confluent_service_account.app_manager.id
  }

  properties = {
    "sql.current-catalog"  = confluent_environment.this.display_name
    "sql.current-database" = confluent_kafka_cluster.this.display_name
  }

  rest_endpoint = data.confluent_flink_region.this.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_flink_api_key.id
    secret = confluent_api_key.app_manager_flink_api_key.secret
  }

  depends_on = [
    confluent_schema.camera_events_value,
  ]
}
