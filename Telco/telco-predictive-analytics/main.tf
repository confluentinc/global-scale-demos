provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "aws" {
  region = var.aws_region
}

provider "docker" {}


resource "aws_db_parameter_group" "postgres_debezium_parameter_group" {
  name   = "${var.project_name}-postgres17-cdc"
  family = "postgres17"

  parameter {
    name  = "rds.logical_replication"
    value = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_security_group" "instance" {
  name = "${var.project_name}-rds-sg"
  ingress {
    from_port   = "5432"
    to_port     = "5432"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres_db" {
  identifier                          = "${var.project_name}-db"
  allocated_storage                   = 100
  engine                              = "postgres"
  engine_version                      = "17.6"
  instance_class                      = "db.t4g.micro"
  port                                = "5432"
  username                            = "postgres"
  password                            = "password"
  parameter_group_name                = aws_db_parameter_group.postgres_debezium_parameter_group.name
  apply_immediately                   = true
  skip_final_snapshot                 = true
  publicly_accessible                 = true
  vpc_security_group_ids              = [aws_security_group.instance.id]
  backup_retention_period             = 0
  depends_on = [
    aws_db_parameter_group.postgres_debezium_parameter_group,
  ]
}

# Long-lived tools container we can exec into
resource "docker_container" "psql_client" {
  name     = "${var.project_name}-psql-client"
  image    = "postgres:16"
  start    = true
  must_run = true

  # Just keep the container running
  command = ["sleep", "infinity"]
}

# Run SQL file inside the container using psql
# Place your SQL in init.sql next to this .tf
resource "null_resource" "run_postgres_init" {
  # Re-run only when SQL changes (or bump this manually)
  triggers = {
    sql_checksum = filesha256("${path.module}/init-v2.sql")
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker cp ${path.module}/init-v2.sql ${var.project_name}-psql-client:/tmp/init-v2.sql
      docker exec ${docker_container.psql_client.name} \
        bash -c "PGPASSWORD='${aws_db_instance.postgres_db.password}' psql \
          -h ${aws_db_instance.postgres_db.address} \
          -p "5432" \
          -U ${aws_db_instance.postgres_db.username} \
          -d "postgres" \
          -v ON_ERROR_STOP=1 \
          -f /tmp/init-v2.sql"
    EOT
  }

  depends_on = [
    docker_container.psql_client,
  ]
}

/*
resource "null_resource" "pgbench_run" {
  triggers = {
    version = "v1"
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm \
        -e PGPASSWORD='${aws_db_instance.postgres_db.password}' \
        -v ${path.module}/generator.sql:/tmp/generator.sql \
        postgres:16 \
        pgbench \
          -h ${aws_db_instance.postgres_db.address} \
          -p 5432 \
          -U ${aws_db_instance.postgres_db.username} \
          -d postgres \
          -f /tmp/generator.sql \
          -c 4 -j 4 -T 300
    EOT
  }

  depends_on = [null_resource.run_postgres_init]
}
*/

resource "confluent_environment" "demo-env" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

resource "docker_image" "sql_generator_image" {
  name = "generate:records-${var.project_name}"
  build {
    context = "${path.module}/sql_generator"
    dockerfile = "Dockerfile"
  }
  depends_on = [ aws_db_parameter_group.postgres_debezium_parameter_group ] 
}

resource "docker_container" "sql_generator_container" {
  name  = "${var.project_name}-sql-generator"
  image = docker_image.sql_generator_image.name
  
  env = [
    "PGHOST=${aws_db_instance.postgres_db.address}",
    "PGUSER=${aws_db_instance.postgres_db.username}",
    "PGPASSWORD=${aws_db_instance.postgres_db.password}",
    "PGDATABASE=postgres",
    "INTERVAL_SECONDS=5",
  ]
  start      = true
  restart    = "on-failure"
  must_run   = true
  depends_on = [null_resource.run_postgres_init]
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
resource "confluent_kafka_cluster" "basic" {
  display_name = "${var.project_name}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  basic {}
  environment {
    id = confluent_environment.demo-env.id
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.demo-env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic,
  ]
}
// 'app-manager' service account is required in this configuration to create 'orders' topic and grant ACLs
// to 'app-producer' and 'app-consumer' service accounts.
resource "confluent_service_account" "app-manager" {
  display_name = "${var.project_name}-app-manager"
  description  = "Service account to manage Kafka cluster"
  depends_on = [
    confluent_environment.demo-env,
  ]
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
  depends_on = [
    confluent_environment.demo-env,
  ]
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "${var.project_name}-app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.demo-env.id
    }
  }

  # The goal is to ensure that confluent_role_binding.app-manager-kafka-cluster-admin is created before
  # confluent_api_key.app-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,
  ]
}

resource "confluent_role_binding" "stream-governance-app-manager" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.essentials.resource_name}/subject=*"
}

resource "confluent_role_binding" "stream-governance-app-manager-data-steward" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "DataSteward"
  crn_pattern = confluent_environment.demo-env.resource_name
}

resource "confluent_role_binding" "stream-governance-app-manager-env-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.demo-env.resource_name
}

resource "confluent_api_key" "stream_governance_api_key" {
  display_name = "demo_stream_governance_api_key"
  description  = "Stream Governance API Key that is owned by app_manager service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.essentials.id
    api_version = data.confluent_schema_registry_cluster.essentials.api_version
    kind        = data.confluent_schema_registry_cluster.essentials.kind

    environment {
      id = confluent_environment.demo-env.id
    }
  }
}

resource "confluent_service_account" "app-connector" {
  display_name = "${var.project_name}-app-connector"
  description  = "Service account of postgre sql db Source Connector to consume from topic of Kafka cluster"
}

resource "confluent_kafka_acl" "app-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "ALL"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
  depends_on = [ confluent_service_account.app-connector ]
}

resource "confluent_kafka_acl" "app-connector-read-on-consumer-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "ALL"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
  depends_on = [ confluent_service_account.app-connector ]
}

resource "confluent_connector" "postgre-sql-cdc-source" {
  environment {
    id = confluent_environment.demo-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "database.password" = "password"
  }

  config_nonsensitive = {
    "connector.class"          = "PostgresCdcSourceV2"
    "name"                     = "${var.project_name}_postgres_connector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-manager.id
    "database.hostname"        = aws_db_instance.postgres_db.address
    "database.port"            = "5432"
    "database.user"            = "postgres"
    "database.dbname"          = "postgres"
    "topic.prefix"             = "demo"
    "slot.name"                = "dbz_slot"
    "publication.name"         = "dbz_publication"
    "table.include.list"       = "telco.*"
    "plugin.name"              = "pgoutput"
    "output.data.format"       = "AVRO"
    "output.key.format"        = "AVRO"
    "tasks.max"                = "1"
    "after.state.only"         = "true"
    "snapshot.mode"            = "initial"
    "decimal.handling.mode"   = "double"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topics,
    null_resource.run_postgres_init,
  ]
}

resource "confluent_flink_compute_pool" "main" {
  display_name     = "${var.project_name}-demo-flink-pool"
  cloud        = "AWS"
  region = var.aws_region
  max_cfu          = 10
  environment {
    id = confluent_environment.demo-env.id
  }
}

data "confluent_flink_region" "flink-region" {
  cloud   = "AWS"
  region  = var.aws_region
}

resource "confluent_role_binding" "app-manager-flink-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.demo-env.resource_name
  depends_on = [ confluent_environment.demo-env ]
}

resource "confluent_api_key" "flink-api-key" {
  display_name = "${var.project_name}-demo-flink-api-key"
  description  = "Flink API Key"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.flink-region.id
    api_version = data.confluent_flink_region.flink-region.api_version
    kind        = data.confluent_flink_region.flink-region.kind

    environment {
      id = confluent_environment.demo-env.id
    }
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_role_binding.app-manager-flink-admin,
  ]
}

resource "confluent_flink_statement" "network_perf_enriched_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
    CREATE TABLE `demo.telco.network_perf_enriched` (
      window_start_ts         TIMESTAMP(3),
      window_end_ts           TIMESTAMP(3),
      tracking_area_id        INT,
      ran_call_success_rate   DOUBLE,
      ran_attach_success_rate DOUBLE,
      ran_handover_success_rate DOUBLE,
      core_call_success_rate  DOUBLE,
      core_attach_success_rate DOUBLE,
      core_handover_success_rate DOUBLE,
      packet_loss_pct         DOUBLE,
      latency_ms              DOUBLE,
      jitter_ms               DOUBLE,
      WATERMARK FOR window_start_ts AS window_start_ts - INTERVAL '30' SECOND
    )
    AS
    WITH ran AS (
      SELECT
        TO_TIMESTAMP(REPLACE(REPLACE(window_start_ts, 'T', ' '), 'Z', '')) AS window_start_ts,
        TO_TIMESTAMP(REPLACE(REPLACE(window_end_ts,   'T', ' '), 'Z', '')) AS window_end_ts,
        tracking_area_id,
        ran_call_success_rate,
        ran_attach_success_rate,
        ran_handover_success_rate
      FROM `demo.telco.fact_ran_performance`
    ),
    core AS (
      SELECT
        TO_TIMESTAMP(REPLACE(REPLACE(window_start_ts, 'T', ' '), 'Z', '')) AS window_start_ts,
        TO_TIMESTAMP(REPLACE(REPLACE(window_end_ts,   'T', ' '), 'Z', '')) AS window_end_ts,
        tracking_area_id,
        core_call_success_rate,
        core_attach_success_rate,
        core_handover_success_rate
      FROM `demo.telco.fact_core_performance`
    ),
    underlay AS (
      SELECT
        TO_TIMESTAMP(REPLACE(REPLACE(window_start_ts, 'T', ' '), 'Z', '')) AS window_start_ts,
        TO_TIMESTAMP(REPLACE(REPLACE(window_end_ts,   'T', ' '), 'Z', '')) AS window_end_ts,
        tracking_area_id,
        packet_loss_pct,
        latency_ms,
        jitter_ms
      FROM `demo.telco.fact_underlay_performance`
    )
    SELECT
      r.window_start_ts,
      r.window_end_ts,
      r.tracking_area_id,
      r.ran_call_success_rate,
      r.ran_attach_success_rate,
      r.ran_handover_success_rate,
      c.core_call_success_rate,
      c.core_attach_success_rate,
      c.core_handover_success_rate,
      u.packet_loss_pct,
      u.latency_ms,
      u.jitter_ms
    FROM ran AS r
    JOIN core AS c
      ON  r.tracking_area_id  = c.tracking_area_id
      AND r.window_start_ts   = c.window_start_ts
      AND r.window_end_ts     = c.window_end_ts
    JOIN underlay AS u
      ON  r.tracking_area_id  = u.tracking_area_id
      AND r.window_start_ts   = u.window_start_ts
      AND r.window_end_ts     = u.window_end_ts;
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
  ]
}

resource "confluent_flink_statement" "call_perf_enriched_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
    CREATE TABLE `demo.telco.call_perf_enriched` (
      call_id               INT,
      imsi                  STRING,
      tracking_area_id      INT,
      serving_gateway_id    INT,
      serving_switch_id     INT,
      start_ts              TIMESTAMP(3),
      end_ts                TIMESTAMP(3),
      clear_code            STRING,
      net_window_start_ts   TIMESTAMP(3),
      net_window_end_ts     TIMESTAMP(3),
      ran_call_success_rate DOUBLE,
      ran_attach_success_rate DOUBLE,
      ran_handover_success_rate DOUBLE,
      core_call_success_rate DOUBLE,
      core_attach_success_rate DOUBLE,
      core_handover_success_rate DOUBLE,
      packet_loss_pct       DOUBLE,
      latency_ms            DOUBLE,
      jitter_ms             DOUBLE,
      WATERMARK FOR start_ts AS start_ts - INTERVAL '30' SECOND
    )
    AS
    WITH calls AS (
      SELECT
        call_id,
        imsi,
        tracking_area_id,
        serving_gateway_id,
        serving_switch_id,
        TO_TIMESTAMP(REPLACE(REPLACE(start_ts, 'T', ' '), 'Z', '')) AS start_ts,
        TO_TIMESTAMP(REPLACE(REPLACE(end_ts,   'T', ' '), 'Z', '')) AS end_ts,
        clear_code
      FROM `demo.telco.fact_call_clear_code`
    )
    SELECT
      cc.call_id,
      cc.imsi,
      cc.tracking_area_id,
      cc.serving_gateway_id,
      cc.serving_switch_id,
      cc.start_ts,
      cc.end_ts,
      cc.clear_code,
      npe.window_start_ts AS net_window_start_ts,
      npe.window_end_ts   AS net_window_end_ts,
      npe.ran_call_success_rate,
      npe.ran_attach_success_rate,
      npe.ran_handover_success_rate,
      npe.core_call_success_rate,
      npe.core_attach_success_rate,
      npe.core_handover_success_rate,
      npe.packet_loss_pct,
      npe.latency_ms,
      npe.jitter_ms
    FROM calls cc
    JOIN `demo.telco.network_perf_enriched` AS npe
      ON cc.tracking_area_id = npe.tracking_area_id
    AND cc.start_ts = npe.window_start_ts
    AND cc.end_ts =  npe.window_end_ts;
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
    confluent_flink_statement.network_perf_enriched_statement,
  ]
}

resource "confluent_flink_statement" "subscriber_perf_enriched_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
    CREATE TABLE `demo.telco.subscriber_perf_enriched` (
    call_id          INT,
    imsi             STRING,
    snapshot_ts       TIMESTAMP(3),
    vlr              STRING,
    calling_state     STRING,
    mdn               STRING,
    imei              STRING,
    version           STRING,
    tracking_area_id    INT,
    serving_gateway_id          INT,
    serving_switch_id           INT,
    start_ts       TIMESTAMP(3),
    end_ts         TIMESTAMP(3),
    clear_code       STRING,
    net_window_start_ts   TIMESTAMP(3),
    net_window_end_ts     TIMESTAMP(3),
    ran_call_success_rate   DOUBLE,
    ran_attach_success_rate DOUBLE,
    ran_handover_success_rate DOUBLE,
    core_call_success_rate     DOUBLE,
    core_attach_success_rate   DOUBLE,
    core_handover_success_rate DOUBLE,
    packet_loss_pct      DOUBLE,
    latency_ms       DOUBLE,
    jitter_ms        DOUBLE,
    WATERMARK FOR start_ts AS start_ts - INTERVAL '30' SECOND
) AS SELECT
    cpe.call_id,
    cpe.imsi,
    TO_TIMESTAMP(REPLACE(REPLACE(ss.snapshot_ts, 'T', ' '), 'Z', '')) AS snapshot_ts,
    ss.vlr,
    ss.calling_state,
    ds.mdn,
    ds.imei,
    ds.version,
    cpe.tracking_area_id,
    cpe.serving_gateway_id,
    cpe.serving_switch_id,
    cpe.start_ts,
    cpe.end_ts,
    cpe.clear_code,
    cpe.net_window_start_ts,
    cpe.net_window_end_ts,
    cpe.ran_call_success_rate,
    cpe.ran_attach_success_rate,
    cpe.ran_handover_success_rate,
    cpe.core_call_success_rate,
    cpe.core_attach_success_rate,
    cpe.core_handover_success_rate,
    cpe.packet_loss_pct,
    cpe.latency_ms,
    cpe.jitter_ms
  FROM `demo.telco.call_perf_enriched` AS cpe
  JOIN `demo.telco.fact_subscriber_state` AS ss
    ON cpe.imsi = ss.imsi
    AND cpe.start_ts = TO_TIMESTAMP(REPLACE(REPLACE(ss.snapshot_ts, 'T', ' '), 'Z', ''))
  JOIN `demo.telco.dim_subscriber` AS ds
    ON cpe.imsi = ds.imsi
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
    confluent_flink_statement.call_perf_enriched_statement,
  ]
}

resource "confluent_flink_statement" "subscriber_perf_issues_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
    CREATE TABLE `demo.telco.subscriber_perf_issues` (
  window_start  TIMESTAMP(3),
  window_end    TIMESTAMP(3),
  imsi          STRING,
  failed_events BIGINT,
  issue_score   BIGINT
) AS SELECT
    window_start,
    window_end,
    imsi,
    COUNT(*) AS failed_events,
    SUM(
      CASE
        WHEN clear_code <> 'NORMAL_CLEARING'
          OR packet_loss_pct > 5
          OR latency_ms > 100
          OR jitter_ms > 5
          OR ran_call_success_rate < 95.0
          OR core_call_success_rate < 95.0
        THEN 1 ELSE 0
      END
    ) AS issue_score
  FROM TABLE(
    TUMBLE(
      TABLE `demo.telco.subscriber_perf_enriched`,
      DESCRIPTOR(start_ts),
      INTERVAL '1' MINUTE
    )
  )
  GROUP BY window_start, window_end, imsi;
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
    confluent_flink_statement.subscriber_perf_enriched_statement,
  ]
}

resource "confluent_flink_statement" "packetloss_result_anomaly_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
  CREATE TABLE `demo.telco.packetloss_result_anomaly` DISTRIBUTED INTO 6 BUCKETS AS
  WITH windowed_avg AS (
    SELECT
      window_start,
      window_end,
      window_time,
      tracking_area_id,
      AVG(packet_loss_pct) AS avg_packet_loss
    FROM
      TUMBLE(TABLE `demo.telco.subscriber_perf_enriched`, DESCRIPTOR(start_ts), INTERVAL '15' SECOND)
    GROUP BY window_start, window_end, window_time, tracking_area_id
  )
  SELECT
  window_start,
  window_end,
  window_time,
  tracking_area_id,
  avg_packet_loss,
  ML_DETECT_ANOMALIES(avg_packet_loss, window_time, JSON_OBJECT('enableStl' VALUE false))
    OVER (
      PARTITION BY tracking_area_id
      ORDER BY window_time
      RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS anomaly
  FROM windowed_avg;
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
    confluent_flink_statement.subscriber_perf_enriched_statement,
  ]
}

resource "confluent_flink_statement" "packetloss_result_anomaly_flatten_statement" {
  organization {
    id = data.confluent_organization.main.id
    }
  environment {
    id = confluent_environment.demo-env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement  = <<-EOT
  CREATE TABLE `demo.telco.packetloss_result_anomaly_flatten` AS SELECT
  window_start             AS window_start_ts,
  window_end               AS window_end_ts,
  window_time              AS window_time,
  tracking_area_id         AS tracking_area_id,
  avg_packet_loss                      AS avg_packet_loss,
  anomaly.`timestamp` AS anomaly_ts,
  anomaly.actual_value                 AS actual_value,
  anomaly.forecast_value               AS forecast_value,
  anomaly.lower_bound                  AS lower_bound,
  anomaly.upper_bound                  AS upper_bound,
  anomaly.is_anomaly                  AS is_anomaly,
  anomaly.rmse                         AS rmse,
  anomaly.aic                          AS aic
  FROM `demo.telco.packetloss_result_anomaly`;
  EOT
  properties = {
    "sql.current-catalog"  = confluent_environment.demo-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  # Use data.confluent_flink_region.main.rest_endpoint for Basic, Standard, public Dedicated Kafka clusters
  # and data.confluent_flink_region.main.private_rest_endpoint for Kafka clusters with private networking
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.postgre-sql-cdc-source,
    confluent_flink_statement.packetloss_result_anomaly_statement,
  ]
}

data "confluent_organization" "main" {}


resource "confluent_api_key" "app-manager-tableflow-api-key" {
  display_name = "${var.project_name}-demo-app-manager-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.demo-env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-provider-integration-resource-owner,
  ]
}


resource "confluent_tableflow_topic" "final-tableflow-topic" {
  environment {
    id = confluent_environment.demo-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name = "demo.telco.packetloss_result_anomaly_flatten"
  table_formats = ["ICEBERG"]
  // Use BYOB AWS storage
  byob_aws {
    bucket_name             = aws_s3_bucket.tableflow_byob_bucket.bucket
    provider_integration_id = confluent_provider_integration.main.id
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }
  depends_on = [
    module.s3_access_role,
    confluent_flink_statement.packetloss_result_anomaly_flatten_statement,
    confluent_provider_integration.main,
  ]
}

resource "confluent_tableflow_topic" "final-tableflow-topic-2" {
  environment {
    id = confluent_environment.demo-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name = "demo.telco.subscriber_perf_enriched"
  table_formats = ["ICEBERG"]
  // Use BYOB AWS storage
  byob_aws {
    bucket_name             = aws_s3_bucket.tableflow_byob_bucket.bucket
    provider_integration_id = confluent_provider_integration.main.id
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }
  depends_on = [
    confluent_tableflow_topic.final-tableflow-topic,
  ]
}

data "aws_caller_identity" "current" {}

locals {
  customer_s3_access_role_name = "${var.project_name}-tableflow-access-role"
  customer_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_s3_access_role_name}"
  glue_access_role_name = "${var.project_name}-glue-access-role"
  glue_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.glue_access_role_name}"  
}

resource "aws_s3_bucket" "tableflow_byob_bucket" {
  bucket = "${var.project_name}-s3-bucket"
  tags = {
    Name        = "Tableflow Demo S3 Bucket"
  }
  force_destroy = true
  depends_on = [
    confluent_environment.demo-env,
  ]
}

resource "aws_s3_bucket_public_access_block" "public_bucket_block" {
  bucket = aws_s3_bucket.tableflow_byob_bucket.id

  # Set to false to allow public policies for read access
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "confluent_provider_integration" "main" {
  display_name = "${var.project_name}_s3_tableflow_integration"
  environment {
    id = confluent_environment.demo-env.id
  }
  aws {
    # During the creation of confluent_provider_integration.main, the S3 role does not yet exist.
    # The role will be created after confluent_provider_integration.main is provisioned
    # by the s3_access_role module using the specified target name.
    # Note: This is a workaround to avoid updating an existing role or creating a circular dependency.
    customer_role_arn = local.customer_s3_access_role_arn
  }
  depends_on = [
    aws_s3_bucket.tableflow_byob_bucket,
  ]
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_environment.demo-env.resource_name}/provider-integration=${confluent_provider_integration.main.id}"

}

resource "confluent_role_binding" "app-manager-glue-provider-integration-resource-owner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_environment.demo-env.resource_name}/provider-integration=${confluent_provider_integration.glue.id}"

}

resource "confluent_provider_integration" "glue" {
  display_name = "${var.project_name}_glue_tableflow_integration"
  environment {
    id = confluent_environment.demo-env.id
  }
  aws {
    # During the creation of confluent_provider_integration.main, the S3 role does not yet exist.
    # The role will be created after confluent_provider_integration.main is provisioned
    # by the s3_access_role module using the specified target name.
    # Note: This is a workaround to avoid updating an existing role or creating a circular dependency.
    customer_role_arn = local.glue_access_role_arn
  }
}

module "s3_access_role" {
  source                           = "./iam_role_module"
  s3_bucket_name                   = aws_s3_bucket.tableflow_byob_bucket.bucket
  provider_integration_role_arn    = confluent_provider_integration.main.aws[0].iam_role_arn
  provider_integration_external_id = confluent_provider_integration.main.aws[0].external_id
  customer_role_name               = local.customer_s3_access_role_name
  customer_policy_name             = "${var.project_name}-tableflow-s3-access-policy"
  depends_on = [
    confluent_environment.demo-env,
  ]
}


resource "confluent_catalog_integration" "glue_tableflow_catalog_integeration" {
  environment {
    id = confluent_environment.demo-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name = "${var.project_name}_glue_tableflow_catalog_integeration"
  aws_glue {
    provider_integration_id = confluent_provider_integration.glue.id
  }
  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }

  depends_on = [
    confluent_role_binding.app-manager-glue-provider-integration-resource-owner,
  ]
}


resource "aws_iam_role" "glue_tableflow_access_role" {
  name = "${local.glue_access_role_name}"
  description = "IAM role for accessing glue with a trust policy for Tableflow"
  
    assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = confluent_provider_integration.glue.aws[0].iam_role_arn
        }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = confluent_provider_integration.glue.aws[0].external_id
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = confluent_provider_integration.glue.aws[0].iam_role_arn
        }
        Action    = "sts:TagSession"
      }
    ]
  })
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration,
  ]
}


resource "aws_iam_policy" "glue_tableflow_access_policy" {
  name        = "${var.project_name}-glue-access-policy"
  description = "IAM policy for accessing glue for Tableflow"

  policy = jsonencode(
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "glue:GetTable",
                "glue:GetDatabase",
                "glue:DeleteTable",
                "glue:DeleteDatabase",
                "glue:CreateTable",
                "glue:CreateDatabase",
                "glue:UpdateTable",
                "glue:UpdateDatabase"
            ],
            "Resource": [
                "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
            ]
        }
    ]
}
    )
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration,
  ]
}

resource "aws_iam_role_policy_attachment" "glue_role_policy_attachment" {
  role       = aws_iam_role.glue_tableflow_access_role.name
  policy_arn = aws_iam_policy.glue_tableflow_access_policy.arn
  depends_on = [
    aws_iam_policy.glue_tableflow_access_policy,
    aws_iam_role.glue_tableflow_access_role,
  ]
}

resource "confluent_service_account" "app-reader" {
  display_name = "${var.project_name}-app-reader"
  description  = "Service account of Iceberg Reader applications or compute engines."
  depends_on = [ confluent_environment.demo-env ]
}

resource "confluent_api_key" "app-reader-tableflow-api-key" {
  display_name = "${var.project_name}-app-reader-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'app-reader' service account"
  owner {
    id          = confluent_service_account.app-reader.id
    api_version = confluent_service_account.app-reader.api_version
    kind        = confluent_service_account.app-reader.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.demo-env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-reader-environment-admin,
  ]
}

// https://docs.confluent.io/cloud/current/topics/tableflow/operate/tableflow-rbac.html#access-to-tableflow-resources
resource "confluent_role_binding" "app-reader-environment-admin" {
  principal   = "User:${confluent_service_account.app-reader.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.demo-env.resource_name
  depends_on = [ confluent_environment.demo-env ]
}

resource "aws_quicksight_data_source" "athena" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_source_id = "${var.project_name}-tableflow-iceberg-tables"
  name           = "${var.project_name}-tableflow-iceberg-tables"
  region = var.aws_region

  type = "ATHENA"

  parameters {
    athena {
      work_group = "primary"
    }
  }

  permission {
    principal = "arn:aws:quicksight:ca-central-1:829250931565:user/default/${var.qs_username}"  # QS user or group ARN
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
  }
  depends_on = [
    confluent_tableflow_topic.final-tableflow-topic-2,
  ]
}

resource "aws_quicksight_data_set" "demo_telco_packetloss_result_anomaly_flatten" {
  aws_account_id = data.aws_caller_identity.current.account_id

  data_set_id = "demo_telco_packetloss_result_anomaly_flatten"
  name        = "demo.telco.packetloss_result_anomaly_flatten"

  import_mode = "DIRECT_QUERY"

  # Map to Glue catalog table via Athena
  physical_table_map {
    physical_table_map_id = "athena-main"

    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = "AwsDataCatalog"
      schema          = confluent_kafka_cluster.basic.id
      name            = "demo.telco.packetloss_result_anomaly_flatten"

      # Define columns as they exist in the Glue table
      input_columns {
        name = "window_start_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "window_end_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "window_time"
        type = "DATETIME"
      }
      input_columns {
        name = "tracking_area_id"
        type = "INTEGER"
      }
      input_columns {
        name = "avg_packet_loss"
        type = "STRING"
      }
      input_columns {
        name = "anomaly_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "actual_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "forecast_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "lower_bound"
        type = "DECIMAL"
      }
      input_columns {
        name = "upper_bound"
        type = "DECIMAL"
      }
      input_columns {
        name = "is_anomaly"
        type = "INTEGER"
      }
      input_columns {
        name = "rmse"
        type = "DECIMAL"
      }
      input_columns {
        name = "aic"
        type = "DECIMAL"
      }
      input_columns {
        name = "$$topic"
        type = "STRING"
      }
      input_columns {
        name = "$$partition"
        type = "INTEGER"
      }
      input_columns {
        name = "$$headers"
        type = "STRING"
      }
      input_columns {
        name = "$$leader_epoch"
        type = "INTEGER"
      }
      input_columns {
        name = "$$offset"
        type = "INTEGER"
      }
      input_columns {
        name = "$$timestamp"
        type = "DATETIME"
      }
      input_columns {
        name = "$$timestamp-type"
        type = "STRING"
      }
    }
  }

  logical_table_map {
    logical_table_map_id = "athena-main"
    alias                = "demo.telco.packetloss_result_anomaly_flatten"

    source {
      physical_table_id = "athena-main"
    }
  }

  permissions {
    principal = "arn:aws:quicksight:ca-central-1:829250931565:user/default/${var.qs_username}" 
    actions = [
      "quicksight:UpdateDataSetPermissions",
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
    ]
  }
  
  depends_on = [
    aws_quicksight_data_source.athena,
  ]
}

resource "aws_quicksight_data_set" "demo_telco_subscriber_perf_enriched" {
  aws_account_id = data.aws_caller_identity.current.account_id

  data_set_id = "demo_telco_subscriber_perf_enriched"
  name        = "demo.telco.subscriber_perf_enriched"

  import_mode = "DIRECT_QUERY"

  # Map to Glue catalog table via Athena
  physical_table_map {
    physical_table_map_id = "athena-main-2"

    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = "AwsDataCatalog"
      schema          = confluent_kafka_cluster.basic.id
      name            = "demo.telco.subscriber_perf_enriched"

      # Define columns as they exist in the Glue table
      input_columns {
        name = "call_id"
        type = "INTEGER"
      }
      input_columns {
        name = "imsi"
        type = "STRING"
      }
      input_columns {
        name = "snapshot_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "vlr"
        type = "STRING"
      }
      input_columns {
        name = "calling_state"
        type = "STRING"
      }
      input_columns {
        name = "mdn"
        type = "STRING"
      }
      input_columns {
        name = "imei"
        type = "STRING"
      }
      input_columns {
        name = "version"
        type = "STRING"
      }
      input_columns {
        name = "tracking_area_id"
        type = "INTEGER"
      }
      input_columns {
        name = "serving_gateway_id"
        type = "INTEGER"
      }
      input_columns {
        name = "serving_switch_id"
        type = "INTEGER"
      }
      input_columns {
        name = "start_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "end_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "clear_code"
        type = "STRING"
      }
      input_columns {
        name = "net_window_start_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "net_window_end_ts"
        type = "DATETIME"
      }
      input_columns {
        name = "ran_call_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "ran_attach_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "ran_handover_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "core_call_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "core_attach_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "core_handover_success_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "packet_loss_pct"
        type = "DECIMAL"
      }
      input_columns {
        name = "latency_ms"
        type = "DECIMAL"
      }
      input_columns {
        name = "jitter_ms"
        type = "DECIMAL"
      }
      input_columns {
        name = "$$topic"
        type = "STRING"
      }
      input_columns {
        name = "$$partition"
        type = "STRING"
      }
      input_columns {
        name = "$$headers"
        type = "STRING"
      }
      input_columns {
        name = "$$leader_epoch"
        type = "INTEGER"
      }
      input_columns {
        name = "$$offset"
        type = "INTEGER"
      }
      input_columns {
        name = "$$timestamp"
        type = "DATETIME"
      }
      input_columns {
        name = "$$timestamp-type"
        type = "STRING"
      }
    }
  }

  logical_table_map {
    logical_table_map_id = "athena-main-2"
    alias                = "demo.telco.subscriber_perf_enriched"

    source {
      physical_table_id = "athena-main-2"
    }
  }

  permissions {
    principal = "arn:aws:quicksight:ca-central-1:829250931565:user/default/${var.qs_username}" 
    actions = [
      "quicksight:UpdateDataSetPermissions",
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
    ]
  }
  
  depends_on = [
    aws_quicksight_data_source.athena,
  ]
}
/*
resource "aws_quicksight_analysis" "anomaly_detection" {
  analysis_id = "anomaly-line-chart"
  name        = "Anomaly Line Chart"

  definition {
    data_set_identifiers_declarations {
      data_set_arn = aws_quicksight_data_set.demo_telco_packetloss_result_anomaly_flatten.arn
      identifier   = "anomaly_ds"
    }

    sheets {
      title    = "Anomaly Detection"
      sheet_id = "AnomalySheet"

      visuals {
        line_chart_visual {
          visual_id = "AnomalyLine"
          title {
            format_text {
              plain_text = "Anomaly over time"
            }
          }

          chart_configuration {
            field_wells {
              line_chart_aggregated_field_wells {
                category {
                  date_dimension_field {
                    field_id = "anomaly_ts"
                    column {
                      data_set_identifier = "anomaly_ds"
                      column_name         = "anomaly_ts"
                    }
                    hierarchy_id = "anomaly_ts"
                    date_granularity = "SECOND"
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "actual_value"
                    column {
                      data_set_identifier = "anomaly_ds"
                      column_name         = "actual_value"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "forecast_value"
                    column {
                      data_set_identifier = "anomaly_ds"
                      column_name         = "forecast_value"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "lower_bound"
                    column {
                      data_set_identifier = "anomaly_ds"
                      column_name         = "lower_bound"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "upper_bound"
                    column {
                      data_set_identifier = "anomaly_ds"
                      column_name         = "upper_bound"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  depends_on = [
    aws_quicksight_data_set.demo_telco_packetloss_result_anomaly_flatten,
  ]
}
*/
data "aws_iam_role" "quicksight_service_role" {
  name = "aws-quicksight-service-role-v0"
}

resource "aws_iam_policy" "quicksight_s3_access" {
  name        = "${var.project_name}-quicksight-s3-access"
  description = "Allow QuickSight service role to read from test-telco-s3-bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "QuickSightListTelcoBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${aws_s3_bucket.tableflow_byob_bucket.bucket}"
      },
      {
        Sid    = "QuickSightGetTelcoObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${aws_s3_bucket.tableflow_byob_bucket.bucket}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "quicksight_s3_access_attach" {
  role       = data.aws_iam_role.quicksight_service_role.name
  policy_arn = aws_iam_policy.quicksight_s3_access.arn
}