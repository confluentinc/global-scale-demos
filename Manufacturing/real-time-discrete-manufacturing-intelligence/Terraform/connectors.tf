resource "confluent_connector" "postgres_cdc_v2" {
  environment { id = data.confluent_environment.target.id }
  kafka_cluster { id = confluent_kafka_cluster.main.id }

  config_sensitive = {
    "database.password" = var.postgres_password
  }

  config_nonsensitive = {
    "connector.class"          = "PostgresCdcSourceV2"
    "name"                     = "${var.name_prefix}-PostgresCdcSourceV2"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connect_sa.id
    "tasks.max" = "1"

    # DB connectivity
    "database.hostname" = var.postgres_host
    "database.port"     = tostring(var.postgres_port)
    "database.user"     = var.postgres_user
    "database.dbname"   = var.postgres_db_name
    "database.sslmode"  = var.postgres_sslmode   # e.g., "prefer", "require", "verify-ca", "verify-full"

    # CDC specifics
    "plugin.name"        = "pgoutput"
    "topic.prefix"       = var.cdc_topic_prefix
    "output.data.format" = var.cdc_output_value_format  # "AVRO" | "JSON_SR" | "PROTOBUF" | "JSON"
    "output.key.format"  = var.cdc_output_key_format     # "AVRO" | "JSON_SR" | "PROTOBUF" | "JSON" | "STRING"
    "slot.name"          = "debezium2"
    "publication.name"   = "dbz_publication2"
    "publication.autocreate.mode" = "all_tables"

    # Optional tuning examples
    "snapshot.mode" = "initial"
    "after.state.only" = "true"
    "table.include.list" = var.cdc_table_include_list
  }

  depends_on = [
    confluent_kafka_acl.cdc_describe_cluster,
    confluent_kafka_acl.cdc_create_on_prefix_topics,
    confluent_kafka_acl.cdc_write_on_prefix_topics,
    null_resource.create_tables
  ]
}

# PostgreSQL Sink (INSERT mode)
resource "confluent_connector" "postgres_sink_insert" {
  environment { id = data.confluent_environment.target.id }
  kafka_cluster { id = confluent_kafka_cluster.main.id }

  config_sensitive = {
    "connection.password" = var.postgres_password
  }

  config_nonsensitive = {
    "connector.class"          = "PostgresSink"
    "name"                     = "${var.name_prefix}-PostgresSink-INSERT"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connect_sa.id
    "tasks.max"                = "1"
    "poll.interval.ms"         = "30000"

    # DB connectivity
    "connection.host" = var.postgres_host
    "connection.port" = tostring(var.postgres_port)
    "connection.user" = var.postgres_user
    "db.name"         = var.postgres_db_name
    "ssl.mode"        = var.postgres_sslmode   # matches sink semantics

    # Topics + mode
    "topics"       = var.sink_insert_topics    # comma-separated topic list
    "input.data.format" = var.sink_insert_value_format # e.g., "AVRO", "JSON_SR", "PROTOBUF"
    "input.key.format"  = var.sink_insert_key_format   # needed if pk.mode=record_key

    "insert.mode"  = "INSERT"
    "auto.create"  = tostring(var.sink_auto_create)
    "auto.evolve"  = tostring(var.sink_auto_evolve)

    # Optional if you need PK handling for INSERT mode (not required unless constraints apply)
    # "pk.mode"   = "record_value"
    # "pk.fields" = "id"
  }

  depends_on = [
    confluent_kafka_acl.sink_insert_read_topics,
    confluent_kafka_acl.sinks_read_consumer_groups,
    confluent_flink_statement.stmt3
  ]
}

# PostgreSQL Sink (UPSERT mode)
resource "confluent_connector" "postgres_sink_upsert" {
  environment { id = data.confluent_environment.target.id }
  kafka_cluster { id = confluent_kafka_cluster.main.id }

  config_sensitive = {
    "connection.password" = var.postgres_password
  }

  config_nonsensitive = {
    "connector.class"          = "PostgresSink"
    "name"                     = "${var.name_prefix}-PostgresSink-UPSERT"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connect_sa.id

    # DB connectivity
    "connection.host" = var.postgres_host
    "connection.port" = tostring(var.postgres_port)
    "connection.user" = var.postgres_user
    "db.name"         = var.postgres_db_name
    "ssl.mode"        = var.postgres_sslmode
    "tasks.max"= "1"

    # Topics + upsert semantics
    "topics"           = var.sink_upsert_topics   # comma-separated
    "input.data.format" = var.sink_upsert_value_format
    "input.key.format"  = var.sink_upsert_key_format

    "insert.mode" = "UPSERT"
    "pk.mode"     = var.sink_upsert_pk_mode       # "kafka" | "record_key" | "record_value"
    "pk.fields"   = var.sink_upsert_pk_fields     # comma-separated fields matching pk.mode
    "auto.create" = tostring(var.sink_auto_create)
    "auto.evolve" = tostring(var.sink_auto_evolve)


  }

  depends_on = [
    confluent_kafka_acl.sink_upsert_read_topics,
    confluent_kafka_acl.sinks_read_consumer_groups,
    confluent_flink_statement.stmt1
  ]
}