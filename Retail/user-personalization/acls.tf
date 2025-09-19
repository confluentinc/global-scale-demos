# ACLs for PostgreSQL Sink Connector to read from Flink topics

# ACL to read from interaction_data topic
resource "confluent_kafka_acl" "postgres_sink_read_interaction_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "interaction_data"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL to read from co_purchase_counts topic
resource "confluent_kafka_acl" "postgres_sink_read_co_purchase_counts" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "co_purchase_counts"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL to read from user_purchase_totals topic
resource "confluent_kafka_acl" "postgres_sink_read_user_purchase_totals" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "user_purchase_totals"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL to read from highly_rated_item_details topic
resource "confluent_kafka_acl" "postgres_sink_read_highly_rated_item_details" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "highly_rated_item_details"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL to read from item_shared_by_user_pair topic
resource "confluent_kafka_acl" "postgres_sink_read_item_shared_by_user_pair" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "item_shared_by_user_pair"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL to read from purchase_windowed_counts topic
resource "confluent_kafka_acl" "postgres_sink_read_purchase_windowed_counts" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "purchase_windowed_counts"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# Consumer group ACL for sink connector
resource "confluent_kafka_acl" "postgres_sink_read_on_consumer_group" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "GROUP"
  resource_name = "connect-PostgresSinkConnector_flink_tables"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# --- ACLs for the custom-connect-worker service account ---
resource "confluent_kafka_acl" "connector_describe_on_cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACLs for DLQ and Connect Group
resource "confluent_kafka_acl" "connector_create_on_dlq_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_acl" "connector_write_on_dlq_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_acl" "connector_read_on_connect_group" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "GROUP"
  resource_name = "connect"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# --- PostgreSQL CDC Source Connector ACLs ---
resource "confluent_kafka_acl" "postgres_cdc_write_on_prefix_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = local.database_server_name
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_acl" "postgres_cdc_create_on_prefix_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = local.database_server_name
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.custom_connect_worker_service_account.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACLs for DynamoDB Source Connector
resource "confluent_kafka_acl" "dynamodb_connector_describe_on_cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.dynamodb_source_service_account.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

# ACL for writing to DynamoDB CDC topics
resource "confluent_kafka_acl" "dynamodb_connector_write_on_target_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = var.dynamodb_topic_prefix
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.dynamodb_source_service_account.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_acl" "dynamodb_connector_create_on_target_topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = var.dynamodb_topic_prefix
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.dynamodb_source_service_account.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}
