# --------------------------------------------------------
# Service Accounts (Connectors)
# --------------------------------------------------------
resource "confluent_service_account" "connectors" {
  display_name = "connectors-${random_id.id.hex}"
  description  = local.description
  lifecycle {
    prevent_destroy = false
  }
}

# --------------------------------------------------------
# Access Control List (ACL)
# --------------------------------------------------------
resource "confluent_kafka_acl" "connectors_source_describe_cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

# New topics for trades_data, transaction_data, and users_data
resource "confluent_kafka_topic" "trades_data" {
   kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
 
  topic_name         = "trades_data"
  
  rest_endpoint      = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_topic" "transaction_data" {
   kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  

  topic_name         = "transaction_data"
 
  rest_endpoint      = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_topic" "users_data" {
  # CORRECTED: environment and kafka_cluster are now 'environment_id' and 'kafka_cluster_id'
  
   kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  topic_name         = "users_data"
  
  rest_endpoint      = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}


# ACLs for USERS topic (users_data)
resource "confluent_kafka_acl" "connectors_source_create_topic_users" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "CREATE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_write_topic_users" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "WRITE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_read_topic_users" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

# ACLs for STOCK_TRADES topic (trades_data)
resource "confluent_kafka_acl" "connectors_source_create_topic_trades_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.trades_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "CREATE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_write_topic_trades_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.trades_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "WRITE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_read_topic_trades_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.trades_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

# ACLs for TRANSACTION topic (transaction_data)
resource "confluent_kafka_acl" "connectors_source_create_topic_transaction_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.transaction_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "CREATE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_write_topic_transaction_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.transaction_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "WRITE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_kafka_acl" "connectors_source_read_topic_transaction_data" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.transaction_data.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}


# DLQ topics (for the connectors) - Assuming a general DLQ prefix is still desired
resource "confluent_kafka_acl" "connectors_source_create_topic_dlq" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "CREATE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}
resource "confluent_kafka_acl" "connectors_source_write_topic_dlq" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "WRITE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}
resource "confluent_kafka_acl" "connectors_source_read_topic_dlq" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}
# Consumer group
resource "confluent_kafka_acl" "connectors_source_consumer_group" {
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  resource_type = "GROUP"
  resource_name = "connect"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.connectors.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.cc_kafka_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_cluster_key.id
    secret = confluent_api_key.app_manager_kafka_cluster_key.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

# --------------------------------------------------------
# Credentials / API Keys
# --------------------------------------------------------
resource "confluent_api_key" "connector_key" {
  display_name = "connector-${var.cc_cluster_name}-key-${random_id.id.hex}"
  description  = local.description
  owner {
    id          = confluent_service_account.connectors.id
    api_version = confluent_service_account.connectors.api_version
    kind        = confluent_service_account.connectors.kind
  }
  managed_resource {
    id          = confluent_kafka_cluster.cc_kafka_cluster.id
    api_version = confluent_kafka_cluster.cc_kafka_cluster.api_version
    kind        = confluent_kafka_cluster.cc_kafka_cluster.kind
    environment {
      id = confluent_environment.cc_handson_env.id
    }
  }
  depends_on = [
    confluent_kafka_acl.connectors_source_create_topic_users,
    confluent_kafka_acl.connectors_source_write_topic_users,
    confluent_kafka_acl.connectors_source_read_topic_users,
    confluent_kafka_acl.connectors_source_create_topic_trades_data,
    confluent_kafka_acl.connectors_source_write_topic_trades_data,
    confluent_kafka_acl.connectors_source_read_topic_trades_data,
    confluent_kafka_acl.connectors_source_create_topic_transaction_data,
    confluent_kafka_acl.connectors_source_write_topic_transaction_data,
    confluent_kafka_acl.connectors_source_read_topic_transaction_data,
    confluent_kafka_acl.connectors_source_create_topic_dlq,
    confluent_kafka_acl.connectors_source_write_topic_dlq,
    confluent_kafka_acl.connectors_source_read_topic_dlq,
    confluent_kafka_acl.connectors_source_consumer_group,
  ]
  lifecycle {
    prevent_destroy = false
  }
}

# --------------------------------------------------------
# Connectors
# --------------------------------------------------------

# datagen_users
resource "confluent_connector" "datagen_users" {
  environment {
    id = confluent_environment.cc_handson_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  config_sensitive = {}
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "${var.use_prefix}datagen_users"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connectors.id
    "kafka.topic"              = confluent_kafka_topic.users_data.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "USERS"
    "tasks.max"                = "1"
    "max.interval"             = "500"
  }
  depends_on = [
    confluent_kafka_acl.connectors_source_create_topic_users,
    confluent_kafka_acl.connectors_source_write_topic_users,
    confluent_kafka_acl.connectors_source_read_topic_users,
    confluent_kafka_acl.connectors_source_create_topic_dlq,
    confluent_kafka_acl.connectors_source_write_topic_dlq,
    confluent_kafka_acl.connectors_source_read_topic_dlq,
    confluent_kafka_acl.connectors_source_consumer_group,
  ]
  lifecycle {
    prevent_destroy = false
  }
}

# datagen_trades_data
resource "confluent_connector" "datagen_trades_data" {
  environment {
    id = confluent_environment.cc_handson_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  config_sensitive = {}
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "${var.use_prefix}datagen_trades_data"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connectors.id
    "kafka.topic"              = confluent_kafka_topic.trades_data.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "STOCK_TRADES"
    "tasks.max"                = "1"
    "max.interval"             = "500"
  }
  depends_on = [
    confluent_kafka_acl.connectors_source_create_topic_trades_data,
    confluent_kafka_acl.connectors_source_write_topic_trades_data,
    confluent_kafka_acl.connectors_source_read_topic_trades_data,
    confluent_kafka_acl.connectors_source_create_topic_dlq,
    confluent_kafka_acl.connectors_source_write_topic_dlq,
    confluent_kafka_acl.connectors_source_read_topic_dlq,
    confluent_kafka_acl.connectors_source_consumer_group,
  ]
  lifecycle {
    prevent_destroy = false
  }
}

# datagen_transaction_data
resource "confluent_connector" "datagen_transaction_data" {
  environment {
    id = confluent_environment.cc_handson_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.cc_kafka_cluster.id
  }
  config_sensitive = {}
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "${var.use_prefix}datagen_transaction_data"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connectors.id
    "kafka.topic"              = confluent_kafka_topic.transaction_data.topic_name
    "output.data.format"       = "AVRO" # Changed from JSON_SR to AVRO
    "quickstart"               = "TRANSACTIONS"
    "tasks.max"                = "1"
    "max.interval"             = "500"
  }
  depends_on = [
    confluent_kafka_acl.connectors_source_create_topic_transaction_data,
    confluent_kafka_acl.connectors_source_write_topic_transaction_data,
    confluent_kafka_acl.connectors_source_read_topic_transaction_data,
    confluent_kafka_acl.connectors_source_create_topic_dlq,
    confluent_kafka_acl.connectors_source_write_topic_dlq,
    confluent_kafka_acl.connectors_source_read_topic_dlq,
    confluent_kafka_acl.connectors_source_consumer_group,
  ]
  lifecycle {
    prevent_destroy = false
  }
}
