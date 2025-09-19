# --- PostgreSQL CDC Source Connector ---
resource "confluent_connector" "postgre_sql_cdc_source" {
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "database.password" = var.db_password
  }

  config_nonsensitive = {
    "connector.class"                = "PostgresCdcSourceV2"
    "name"                           = "${var.project_name}-PostgresCdcSourceConnector"
    "kafka.auth.mode"                = "SERVICE_ACCOUNT"
    "kafka.service.account.id"       = confluent_service_account.custom_connect_worker_service_account.id
    "database.hostname"              = substr(aws_db_instance.postgresql.endpoint, 0, length(aws_db_instance.postgresql.endpoint) - 5)
    "database.port"                  = var.postgres_db_port
    "database.user"                  = var.db_username
    "database.dbname"                = var.postgres_db_name
    "topic.prefix"                   = "${local.database_server_name}"
    "plugin.name"                    = "pgoutput"
    "output.data.format"             = "AVRO"
    "output.key.format"              = "AVRO"
    "key.converter"                  = "io.confluent.connect.avro.AvroConverter"
    "value.converter"                = "io.confluent.connect.avro.AvroConverter"
    "key.converter.schemas.enable"   = "true"
    "value.converter.schemas.enable" = "true"
    "tasks.max"                      = var.postgres_connector_tasks_max
    "database.sslmode"               = var.postgres_db_sslmode
    "after.state.only"               = var.postgres_after_state_only
    "table.include.list"             = var.postgres_table_include_list
  }

  depends_on = [
    confluent_kafka_acl.connector_describe_on_cluster,
    confluent_kafka_acl.postgres_cdc_write_on_prefix_topics,
    confluent_kafka_acl.postgres_cdc_create_on_prefix_topics,
    aws_db_instance.postgresql,
    null_resource.run_postgres_prerequisites_script
  ]
}

# DynamoDB CDC Source Connector
resource "confluent_connector" "dynamodb_cdc_source" {
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "aws.access.key.id"     = var.access_key
    "aws.secret.access.key" = var.secret_key
  }

  config_nonsensitive = {
    "connector.class"                    = "DynamoDbCdcSource"
    "name"                              = "${var.project_name}-DynamoDbCdcSourceConnector"
    "kafka.auth.mode"                   = "SERVICE_ACCOUNT"
    "kafka.service.account.id"          = confluent_service_account.dynamodb_source_service_account.id
    "aws.region"                        = var.aws_region
    "output.data.format"                = "AVRO"
    "dynamodb.service.endpoint"         = "dynamodb.us-east-1.amazonaws.com"
    "dynamodb.table.discovery.mode"     = var.dynamodb_table_discovery_mode
    "dynamodb.table.sync.mode"          = var.dynamodb_table_sync_mode
    "dynamodb.table.includelist"        = aws_dynamodb_table.user_personalization.name
    "max.batch.size"                    = var.dynamodb_max_batch_size
    "poll.linger.ms"                    = var.dynamodb_poll_linger_ms
    "dynamodb.snapshot.max.poll.records" = var.dynamodb_snapshot_max_poll_records
    "dynamodb.cdc.max.poll.records"     = var.dynamodb_cdc_max_poll_records
    "tasks.max"                         = var.dynamodb_connector_tasks_max
    "transforms"                        = "transform_0"
    "transforms.transform_0.type"       = "org.apache.kafka.connect.transforms.ExtractField$Value"
    "transforms.transform_0.field"      = "after"
  }

  depends_on = [
    confluent_kafka_acl.dynamodb_connector_describe_on_cluster,
    confluent_kafka_acl.dynamodb_connector_write_on_target_topics,
    confluent_kafka_acl.dynamodb_connector_create_on_target_topics,
    aws_dynamodb_table.user_personalization
  ]
}

# Postgres Sink Connector
resource "confluent_connector" "postgres_sink_all_flink_tables" {
  environment {
    id = data.confluent_environment.existing_staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "connection.password" = var.db_password
  }

  config_nonsensitive = {
    "connector.class"                                           = "PostgresSink"
    "name"                                                     = "${var.project_name}-PostgresSinkConnector-flink-tables"
    "kafka.auth.mode"                                          = "SERVICE_ACCOUNT"
    "kafka.service.account.id"                                 = confluent_service_account.custom_connect_worker_service_account.id
    
    # Database connection
    "connection.host"                                          = substr(aws_db_instance.postgresql.endpoint, 0, length(aws_db_instance.postgresql.endpoint) - 5)
    "connection.port"                                          = var.postgres_db_port
    "connection.user"                                          = var.db_username
    "db.name"                                                  = var.postgres_db_name
    "ssl.mode"                                                 = "prefer"
    
    # Topics and data format 
    "topics"                                                   = "co_purchase_counts,highly_rated_item_details,item_shared_by_user_pair,purchase_windowed_counts,user_purchase_totals,interaction_data"
    "input.data.format"                                        = "AVRO"
    "input.key.format"                                         = "AVRO"
    "schema.context.name"                                      = "default"
    
    # Insert behavior
    "insert.mode"                                              = "INSERT"
    "delete.enabled"                                           = "false"
    "auto.create"                                              = "true"
    "auto.evolve"                                              = "true"
    "quote.sql.identifiers"                                    = "ALWAYS"
    
    # Performance and error handling
    "batch.sizes"                                              = "3000"
    "max.poll.interval.ms"                                     = "300000"
    "max.poll.records"                                         = "500"
    "tasks.max"                                                = "1"
    "errors.tolerance"                                         = "all"
    "auto.restart.on.user.error"                               = "true"
    
    # Schema and timezone settings
    "table.types"                                              = "TABLE"
    "db.timezone"                                              = "UTC"
    "timestamp.precision.mode"                                 = "microseconds"
    "date.timezone"                                            = "DB_TIMEZONE"
    
    # Converter settings
    "value.converter.decimal.format"                           = "BASE64"
    "value.converter.reference.subject.name.strategy"          = "DefaultReferenceSubjectNameStrategy"
    "value.converter.value.subject.name.strategy"              = "TopicNameStrategy"
    "key.converter.key.subject.name.strategy"                  = "TopicNameStrategy"
    "value.converter.ignore.default.for.nullables"            = "false"
  }

  depends_on = [
    confluent_flink_statement.insert_interaction_data,
    confluent_flink_statement.insert_co_purchase_counts,
    confluent_flink_statement.insert_user_purchase_totals,
    confluent_flink_statement.insert_highly_rated_item_details,
    confluent_flink_statement.insert_item_shared_by_user_pair,
    confluent_flink_statement.insert_purchase_windowed_counts,
    # ACL dependencies
    confluent_kafka_acl.postgres_sink_read_interaction_data,
    confluent_kafka_acl.postgres_sink_read_co_purchase_counts,
    confluent_kafka_acl.postgres_sink_read_user_purchase_totals,
    confluent_kafka_acl.postgres_sink_read_highly_rated_item_details,
    confluent_kafka_acl.postgres_sink_read_item_shared_by_user_pair,
    confluent_kafka_acl.postgres_sink_read_purchase_windowed_counts,
    confluent_kafka_acl.postgres_sink_read_on_consumer_group
  ]
}
