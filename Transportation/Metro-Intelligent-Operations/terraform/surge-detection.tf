# Phase 2: turns the live headcount stream into a real-time surge alert --
# pinned to a specific station, not just a whole line -- but only for real,
# statistically-detected surges, not on every routine window, so Bedrock is
# invoked as rarely as the data allows.
#
#   metro_train_departures (1-min, per-train totals -- see ../flink-sql/02_*.sql)
#     -> metro_station_headcounts        (5-min tumble, per line+direction+station;
#                                          04_station_headcounts.sql)
#     -> metro_station_anomaly_scores    (ML_DETECT_ANOMALIES, ARIMA-based,
#                                          partitioned per line+direction+station;
#                                          05_station_anomaly_scores.sql)
#     -> metro_station_surge_anomalies   (trailing-baseline average + keeps
#                                          only surges >= 1.5x that baseline;
#                                          JSON output so live-map can read it
#                                          without Schema Registry creds;
#                                          06_station_surge_anomalies.sql)
#     -> metro_station_surge_recommendations  (ML_PREDICT against a Bedrock
#                                          Claude model -- one call per detected
#                                          surge row only; 07/08_*.sql)
#
# live-map/server.py consumes metro_station_surge_anomalies directly (fast,
# no Bedrock round-trip) to draw a highlight circle on the map; the Bedrock
# recommendation is a slower-arriving, optional narrative on top of that.
#
# Set enable_surge_detection = false (the default) to skip this whole phase,
# e.g. if you don't have Bedrock access yet -- nothing else in this project
# depends on it.

resource "confluent_flink_statement" "line_direction_headcounts" {
  count = var.enable_surge_detection ? 1 : 0

  statement = file("${path.module}/../flink-sql/04_station_headcounts.sql")

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
    confluent_flink_statement.train_departure_totals,
  ]
}

resource "confluent_flink_statement" "station_anomaly_scores" {
  count = var.enable_surge_detection ? 1 : 0

  statement = file("${path.module}/../flink-sql/05_station_anomaly_scores.sql")

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
    confluent_flink_statement.line_direction_headcounts,
  ]
}

resource "confluent_flink_statement" "line_surge_anomalies" {
  count = var.enable_surge_detection ? 1 : 0

  statement = file("${path.module}/../flink-sql/06_station_surge_anomalies.sql")

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
    confluent_flink_statement.station_anomaly_scores,
  ]
}

# AWS Bedrock connection -- credentials live only here (and in Terraform
# state, so keep tfstate secure), never inlined into a SQL statement.
resource "confluent_flink_connection" "bedrock" {
  count = var.enable_surge_detection ? 1 : 0

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
  rest_endpoint = data.confluent_flink_region.this.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_flink_api_key.id
    secret = confluent_api_key.app_manager_flink_api_key.secret
  }

  display_name   = "metro-bedrock-connection"
  type           = "BEDROCK"
  endpoint       = var.bedrock_model_endpoint
  aws_access_key = var.bedrock_aws_access_key
  aws_secret_key = var.bedrock_aws_secret_key
}

resource "confluent_flink_statement" "create_bedrock_model" {
  count = var.enable_surge_detection ? 1 : 0

  statement = file("${path.module}/../flink-sql/07_create_bedrock_model.sql")

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
    confluent_flink_connection.bedrock,
  ]
}

resource "confluent_flink_statement" "surge_recommendations" {
  count = var.enable_surge_detection ? 1 : 0

  statement = file("${path.module}/../flink-sql/08_station_surge_recommendations.sql")

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
    confluent_flink_statement.line_surge_anomalies,
    confluent_flink_statement.create_bedrock_model,
  ]
}
