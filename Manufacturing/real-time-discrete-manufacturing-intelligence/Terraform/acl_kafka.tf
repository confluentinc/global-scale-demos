locals {
  kafka_rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
}

resource "confluent_kafka_acl" "cdc_describe_cluster" {
  kafka_cluster { id = confluent_kafka_cluster.main.id }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  host          = "*"
  operation     = "ALL"
  permission    = "ALLOW"
  principal     = "User:${confluent_service_account.connect_sa.id}"
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
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connect_sa.id}"
  host          = "*"
  operation     = "ALL"
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

resource "confluent_role_binding" "flink-admin" {
  principal     = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
  depends_on = [ confluent_environment.confluent_project_env ]
}
