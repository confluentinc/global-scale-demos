locals {
  kafka_rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
}

resource "confluent_kafka_acl" "cdc_describe_cluster" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "cdc_create_on_prefix_topics" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = var.cdc_topic_prefix
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "cdc_write_on_prefix_topics" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = var.cdc_topic_prefix
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}
locals {
  insert_topics = [
    for t in split(",", var.sink_insert_topics) : trimspace(t)
    if trimspace(t) != ""
  ]

  upsert_topics = [
    for t in split(",", var.sink_upsert_topics) : trimspace(t)
    if trimspace(t) != ""
  ]
}
# -----------------------------------------------------------------------------
# ACLs for Sink connectors
# - READ on sink topics
# - READ on consumer groups (prefix "connect-")
# -----------------------------------------------------------------------------
resource "confluent_kafka_acl" "sink_insert_read_topics" {
  for_each = toset(local.insert_topics)

  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = each.key
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "sink_upsert_read_topics" {
  for_each = toset(local.upsert_topics)

  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = each.key
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "sinks_read_consumer_groups" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "GROUP"
  resource_name = "connect-"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"

  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}
resource "confluent_kafka_acl" "flink_describe_cluster" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.flink_sa.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

# Sink topics your statements will create/write
resource "confluent_kafka_acl" "flink_sink_topic_create" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = "production_metrics_sink"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.flink_sa.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "flink_sink_topic_write" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = "production_metrics_sink"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.flink_sa.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "flink_history_topic_create" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = "production_metrics_history"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.flink_sa.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

resource "confluent_kafka_acl" "flink_history_topic_write" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "TOPIC"
  resource_name = "production_metrics_history"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.flink_sa.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = local.kafka_rest_endpoint
  credentials {
    key    = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}
