terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.17.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.76.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}


data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

# Only pick subnets in the default VPC that auto-assign public IPs (i.e. public subnets)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

resource "aws_db_subnet_group" "postgres_public_subnet_group" {
  name       = "${var.project_name}-public-subnet-group"
  subnet_ids = data.aws_subnets.public.ids
}

resource "aws_security_group" "instance" {
  name = "${var.project_name}-sg"
  ingress {
    from_port   = var.postgres_database_port
    to_port     = var.postgres_database_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_parameter_group" "postgres_debezium_parameter_group" {
  name   = replace("${var.project_name}-postgres-parameter-group", "_", "-")
  family = "postgres18"

  # Required parameter for Debezium to perform Change Data Capture (CDC) in PostgreSQL
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "postgres_db" {
  identifier              = replace("${var.project_name}-postgres", "_", "-")
  allocated_storage       = 100
  engine                  = "postgres"
  engine_version          = "18.3"
  instance_class          = "db.t3.medium"
  port                    = var.postgres_database_port
  username                = var.postgres_database_username
  password                = var.postgres_database_password
  parameter_group_name    = aws_db_parameter_group.postgres_debezium_parameter_group.name
  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = true
  vpc_security_group_ids  = [aws_security_group.instance.id]
  db_subnet_group_name    = aws_db_subnet_group.postgres_public_subnet_group.name
  storage_encrypted       = true
  backup_retention_period = 3

  depends_on = [
    aws_db_parameter_group.postgres_debezium_parameter_group,
    aws_db_subnet_group.postgres_public_subnet_group
  ]
}

resource "aws_iam_user" "payments_app_user" {
  name = "${var.project_name}-csfle-user"
}

resource "aws_iam_user_policy" "payments_app_iam_policy" {
  name = "${var.project_name}-kms-policy"
  user = aws_iam_user.payments_app_user.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_key" "csfle_key" {
  description = "A symmetric encryption KMS key used for CSFLE"
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "123"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "${data.aws_caller_identity.current.arn}"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Enable Any IAM User Permission to DESCRIBE"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        },
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        },
        Action = [
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ],
        Resource = "*"
      }
    ]
  })
  depends_on = [aws_iam_user.payments_app_user]
}

resource "confluent_environment" "confluent_project_env" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ADVANCED"
  }
}

data "confluent_schema_registry_cluster" "advanced" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic
  ]
}


resource "confluent_schema_registry_kek" "aws_kms_csfle_key" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name        = "CSFLE_Key"
  kms_type    = "aws-kms"
  kms_key_id  = aws_kms_key.csfle_key.arn
  hard_delete = true
  shared      = true


  depends_on = [
    aws_kms_key.csfle_key,
    confluent_role_binding.stream-governance-app-manager,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_service_account.app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin
  ]
}

resource "confluent_kafka_cluster" "basic" {
  display_name = "${var.project_name}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  basic {}
  environment {
    id = confluent_environment.confluent_project_env.id
  }
}


resource "confluent_service_account" "app-manager" {
  display_name = "${var.project_name}-app-manager"
  description  = "Service account to manage Kafka cluster"
  depends_on   = [confluent_environment.confluent_project_env]
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
  depends_on  = [confluent_environment.confluent_project_env]
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
      id = confluent_environment.confluent_project_env.id
    }
  }
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}


resource "confluent_role_binding" "stream-governance-app-manager" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.advanced.resource_name}/subject=*"
}

resource "confluent_role_binding" "app-manager-kek-rb" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.advanced.resource_name}/kek=CSFLE_Key"
}

resource "confluent_role_binding" "app-connector-kek-rb" {
  principal   = "User:${confluent_service_account.app-connector.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.advanced.resource_name}/kek=CSFLE_Key"
}

resource "confluent_role_binding" "stream-governance-app-manager-environment-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
}

resource "confluent_role_binding" "app-connector-environment-admin" {
  principal   = "User:${confluent_service_account.app-connector.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
}
resource "confluent_api_key" "stream_governance_api_key" {
  display_name = "${var.project_name}_stream_governance_api_key"
  description  = "Stream Governance API Key that is owned by ${var.project_name}_tf_app_manager service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.advanced.id
    api_version = data.confluent_schema_registry_cluster.advanced.api_version
    kind        = data.confluent_schema_registry_cluster.advanced.kind

    environment {
      id = confluent_environment.confluent_project_env.id
    }
  }
}

resource "confluent_service_account" "app-connector" {
  display_name = "${var.project_name}-app-connector567"
  description  = "Service account of Postgres CDC SourceConnector"
  depends_on   = [confluent_environment.confluent_project_env]
}

resource "confluent_role_binding" "app-connector-env-rb" {
  principal   = "User:${confluent_service_account.app-connector.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
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
}



resource "confluent_kafka_acl" "app-connector-write-on-target-topic" {
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
}

resource "confluent_kafka_topic" "sr-dlq-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = "failed-encryption-records"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "user_profiles" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = "psql.public.user_profiles"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_schema" "user_profiles_key" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  subject_name  = "psql.public.user_profiles-key"
  format        = "AVRO"
  schema        = file("./assets/schemas/user_profiles_key.avsc")
  hard_delete   = true
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  depends_on = [
    confluent_kafka_topic.user_profiles,
    confluent_service_account.app-connector,
    confluent_service_account.app-manager,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_role_binding.stream-governance-app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin,
    confluent_schema_registry_kek.aws_kms_csfle_key
  ]
}

resource "confluent_schema" "user_profiles_value" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  subject_name  = "psql.public.user_profiles-value"
  format        = "AVRO"
  hard_delete   = true
  schema        = file("./assets/schemas/user_profiles_value.avsc")
  ruleset {
    domain_rules {
      name       = "PIIEncryption"
      kind       = "TRANSFORM"
      type       = "ENCRYPT"
      mode       = "WRITEREAD"
      tags       = ["PII"]
      on_failure = "DLQ,DLQ"
      params = {
        "encrypt.kek.name" = "CSFLE_Key",
        "dlq.topic"        = "failed-encryption-records"

      }
    }
  }
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  depends_on = [
    confluent_kafka_topic.user_profiles,
    confluent_service_account.app-connector,
    confluent_service_account.app-manager,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_role_binding.stream-governance-app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin,
    confluent_schema_registry_kek.aws_kms_csfle_key
  ]
}


locals {
  tags = {
    PII = "PII Fields"
  }
}

resource "confluent_tag" "this" {
  for_each = local.tags

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }

  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint

  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name        = each.key
  description = each.value
  depends_on = [
    confluent_environment.confluent_project_env,
    confluent_service_account.app-connector,
    confluent_service_account.app-manager,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_role_binding.stream-governance-app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin
  ]
}

resource "local_file" "docker_config_ini" {
  filename   = "${path.module}/assets/datagen/config.ini"
  content    = <<EOT
[kafka]
bootstrap.servers = ${replace(confluent_kafka_cluster.basic.bootstrap_endpoint, "SASL_SSL://", "")}
security.protocol = SASL_SSL
sasl.mechanisms   = PLAIN
sasl.username     = ${confluent_api_key.app-manager-kafka-api-key.id}
sasl.password     = ${confluent_api_key.app-manager-kafka-api-key.secret}
topic.name        = payments

[schema_registry]
url                  = ${data.confluent_schema_registry_cluster.advanced.rest_endpoint}
basic.auth.user.info = ${confluent_api_key.stream_governance_api_key.id}:${confluent_api_key.stream_governance_api_key.secret}

[postgresql]
host     = ${aws_db_instance.postgres_db.address}
database = ${var.postgres_database_name}
user     = ${var.postgres_database_username}
password = ${var.postgres_database_password}
port     = ${var.postgres_database_port}

[simulation]
target_tps                   = 10
valid_transaction_percentage = 95.0
user_pool_size               = 100
EOT
  depends_on = [aws_db_instance.postgres_db]
}

resource "docker_image" "python_datagen_app" {
  name = "${var.project_name}-datagen-app:latest"
  build {
    context    = "${path.module}/assets/datagen/"
    dockerfile = "Dockerfile"
  }
  depends_on = [local_file.docker_config_ini]
}


resource "docker_container" "python_datagen_app_container" {
  name  = "${var.project_name}-datagen-container"
  image = docker_image.python_datagen_app.image_id

  depends_on = [
    docker_image.python_datagen_app
  ]
}


resource "confluent_connector" "postgres" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "database.password" = "${var.postgres_database_password}"
  }

  config_nonsensitive = {
    "connector.class"          = "PostgresCdcSourceV2"
    "name"                     = "${var.project_name}-postgres-cdc-connector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "tasks.max"                = "1"
    "database.hostname"        = aws_db_instance.postgres_db.address
    "database.include.list"    = var.postgres_database_name
    "database.port"            = var.postgres_database_port
    "database.user"            = var.postgres_database_username
    "database.dbname"          = var.postgres_database_name
    "output.data.format"       = "AVRO"
    "output.key.format"        = "AVRO"
    "topic.prefix"             = "psql"
    "snapshot.mode"            = "when_needed"
    "csfle.enabled"            = "true"
    "sr.service.account.id"    = confluent_service_account.app-manager.id
    "slot.name"                = "debezium_tf"
    "publication.name"         = "dbz_publication_tf",

  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic,
    confluent_schema_registry_kek.aws_kms_csfle_key,
    confluent_kafka_topic.sr-dlq-topic,
    confluent_kafka_topic.user_profiles,
    docker_container.python_datagen_app_container,
    confluent_schema.user_profiles_key,
    confluent_schema.user_profiles_value,


  ]
}


data "confluent_organization" "main" {}

resource "confluent_flink_compute_pool" "main" {
  display_name = "${var.project_name}-flink-pool"
  cloud        = "AWS"
  region       = var.aws_region
  max_cfu      = 10
  environment {
    id = confluent_environment.confluent_project_env.id
  }
}

data "confluent_flink_region" "flink-region" {
  cloud  = "AWS"
  region = var.aws_region
}

resource "confluent_role_binding" "app-manager-flink-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
  depends_on  = [confluent_environment.confluent_project_env]
}

resource "confluent_api_key" "flink-api-key" {
  display_name = "${var.project_name}-flink-api-key"
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
      id = confluent_environment.confluent_project_env.id
    }
  }
  depends_on = [
    confluent_flink_compute_pool.main
  ]
}


resource "confluent_flink_statement" "create_account_daily_ledger_table" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "CREATE TABLE `account_daily_ledger` (  `account_no` VARCHAR(2147483647) NOT NULL,  `window_start` TIMESTAMP(3) NOT NULL,  `window_end` TIMESTAMP(3) NOT NULL,  `total_received_amount_5min` DOUBLE NOT NULL,  `total_debited_amount_5min` DOUBLE NOT NULL,  `net_amount_change_5min` DOUBLE NOT NULL,  `total_credit_transactions_5min` BIGINT NOT NULL,  `total_debit_transactions_5min` BIGINT NOT NULL,  `total_combined_transactions_5min` BIGINT NOT NULL,  PRIMARY KEY (account_no) NOT ENFORCED);"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_connector.postgres
  ]
}


resource "confluent_flink_statement" "insert_account_daily_ledger_query" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "insert into account_daily_ledger WITH normalized_ledger AS ( SELECT payee_account_no AS account_no, amount AS received_amount, 0 AS debited_amount, `$rowtime` AS rt FROM payments UNION ALL SELECT payer_account_no AS account_no, 0 AS received_amount, amount AS debited_amount, `$rowtime` AS rt FROM payments ) SELECT account_no, window_start, window_end, SUM(received_amount) AS total_received_amount_5min, SUM(debited_amount) AS total_debited_amount_5min, (SUM(received_amount) - SUM(debited_amount)) AS net_amount_change_5min, COUNT(CASE WHEN received_amount > 0 THEN 1 END) AS total_credit_transactions_5min, COUNT(CASE WHEN debited_amount > 0 THEN 1 END) AS total_debit_transactions_5min, COUNT(*) AS total_combined_transactions_5min FROM TABLE( TUMBLE(TABLE normalized_ledger, DESCRIPTOR(rt), INTERVAL '5' MINUTE)) GROUP BY account_no, window_start, window_end;"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_flink_statement.create_account_daily_ledger_table
  ]
}


resource "confluent_flink_statement" "create_fraudulent_alerts_table" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "CREATE TABLE fraudulent_alerts (user_id STRING,    transaction_id STRING,    alert_type STRING,    reason STRING,    alert_timestamp TIMESTAMP(3),    PRIMARY KEY (user_id) NOT ENFORCED );"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_connector.postgres
  ]
}


resource "confluent_flink_statement" "insert_fraudulent_alerts_query" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "INSERT INTO fraudulent_alerts WITH flattened_payments AS ( SELECT transaction_id, user_id, user_name, device_id, payment_method, amount, `$rowtime` as ts, address.country AS country FROM payments ), impossible_travel_alerts AS (SELECT user_id,fraudulent_txn_id AS transaction_id,'IMPOSSIBLE_TRAVEL' AS alert_type,'User traveled from ' || first_country || ' to ' || second_country || ' in ' || CAST(TIMESTAMPDIFF(MINUTE, first_txn_time, second_txn_time) AS STRING) || ' minutes.' AS reason, CAST(second_txn_time AS TIMESTAMP_LTZ(3)) AS alert_timestamp FROM flattened_payments MATCH_RECOGNIZE (PARTITION BY user_id ORDER BY ts MEASURES CURR_TXN.transaction_id AS fraudulent_txn_id, PREV_TXN.country AS first_country, CURR_TXN.country AS second_country, PREV_TXN.ts AS first_txn_time, CURR_TXN.ts AS second_txn_time ONE ROW PER MATCH AFTER MATCH SKIP TO NEXT ROW PATTERN (PREV_TXN CURR_TXN) DEFINE CURR_TXN AS CURR_TXN.country <> PREV_TXN.country AND CURR_TXN.ts <= PREV_TXN.ts + INTERVAL '10' MINUTE )), device_switch_alerts AS ( SELECT user_id, fraudulent_txn_id AS transaction_id, 'FREQUENT_DEVICE_SWITCH' AS alert_type, 'Payment initiated from device_id ' || first_device_id || ' and device_id ' || second_device_id || ' in ' ||  CAST(TIMESTAMPDIFF(SECOND, first_txn_time, second_txn_time) AS STRING) || ' seconds interval.' AS reason, CAST(second_txn_time AS TIMESTAMP_LTZ(3)) AS alert_timestamp FROM flattened_payments MATCH_RECOGNIZE ( PARTITION BY user_id ORDER BY ts MEASURES CURR_TXN.transaction_id AS fraudulent_txn_id, PREV_TXN.device_id AS first_device_id, CURR_TXN.device_id AS second_device_id, PREV_TXN.ts AS first_txn_time, CURR_TXN.ts AS second_txn_time ONE ROW PER MATCH AFTER MATCH SKIP TO NEXT ROW PATTERN (PREV_TXN CURR_TXN) DEFINE CURR_TXN AS CURR_TXN.device_id <> PREV_TXN.device_id AND CURR_TXN.ts <= PREV_TXN.ts + INTERVAL '1' MINUTE )), amount_anomaly_alerts AS (SELECT user_id, transaction_id, 'AMOUNT_ANOMALY' AS alert_type, 'Transaction amount of ' || CAST(amount AS STRING) || ' flagged as an anomaly with 95% confidence.' AS reason, CAST(ts AS TIMESTAMP_LTZ(3)) AS alert_timestamp FROM ( SELECT user_id, transaction_id, amount, ts, ML_DETECT_ANOMALIES(amount, ts, JSON_OBJECT('minTrainingSize' VALUE 10, 'confidencePercentage' VALUE 95.0, 'enableStl' VALUE false )) OVER ( PARTITION BY user_id ORDER BY ts RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW ) AS anomaly_results FROM flattened_payments ) WHERE anomaly_results[6] IS True AND amount > 1000 ) SELECT * FROM impossible_travel_alerts UNION ALL SELECT * FROM device_switch_alerts UNION ALL SELECT * FROM amount_anomaly_alerts;"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_flink_statement.create_fraudulent_alerts_table
  ]
}


resource "confluent_flink_statement" "create_upsell_opportunities_table" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "CREATE TABLE upsell_opportunities (account_no STRING, window_end TIMESTAMP(3), lead_type STRING, recommended_product STRING, priority STRING, trigger_metric_value DECIMAL(18, 2), PRIMARY KEY(account_no) NOT ENFORCED) WITH ('changelog.mode'='upsert');"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_flink_statement.insert_account_daily_ledger_query,
    confluent_connector.postgres
  ]
}


resource "confluent_flink_statement" "insert_upsell_opportunities_query" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = confluent_service_account.app-manager.id
  }
  statement = "INSERT INTO upsell_opportunities SELECT account_no, window_end, CASE WHEN total_debited_amount_5min >= 5000 THEN 'HIGH_DEBIT_VOLUME' WHEN total_debit_transactions_5min >= 10 THEN 'HIGH_DEBIT_FREQUENCY' WHEN total_received_amount_5min >= 5000 THEN 'HIGH_CREDIT_VOLUME' WHEN total_combined_transactions_5min >= 10 THEN 'HIGH_VELOCITY_MERCHANT' ELSE 'STANDARD_ACTIVITY' END AS lead_type, CASE WHEN total_debited_amount_5min >= 5000 THEN 'Corporate Credit Card / Working Capital Line' WHEN total_debit_transactions_5min >= 10 THEN 'Automated Debit Accounts / Batch Payables API' WHEN total_received_amount_5min >= 5000 THEN 'High-Yield Investment Product / Managed Portfolio' WHEN total_combined_transactions_5min >= 10 THEN 'Premium Merchant Services / POS Upgrade' ELSE 'None' END AS recommended_product, CASE WHEN total_debited_amount_5min >= 10000 OR total_received_amount_5min >= 10000 THEN 'HIGH' ELSE 'MEDIUM' END AS priority, CASE WHEN total_debited_amount_5min >= 5000 THEN total_debited_amount_5min ELSE total_received_amount_5min END AS trigger_metric_value FROM account_daily_ledger WHERE total_debited_amount_5min >= 5000 OR total_debit_transactions_5min >= 10 OR total_received_amount_5min >= 5000 OR total_combined_transactions_5min >= 10;"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.flink-region.rest_endpoint
  credentials {
    key    = confluent_api_key.flink-api-key.id
    secret = confluent_api_key.flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    docker_container.python_datagen_app_container,
    confluent_flink_statement.create_upsell_opportunities_table
  ]
}


locals {
  customer_s3_access_role_name = "${var.project_name}-tableflow-access-role"
  customer_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_s3_access_role_name}"

}

resource "aws_s3_bucket" "tableflow_byob_bucket" {
  bucket = replace("${var.project_name}-s3-bucket", "_", "-")
  tags = {
    Name = "Tableflow Demo S3 Bucket"
  }
  force_destroy = true
  depends_on    = [confluent_environment.confluent_project_env]
}

resource "confluent_provider_integration" "main" {
  display_name = "${var.project_name}_s3_tableflow_integration"
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  aws {
    customer_role_arn = local.customer_s3_access_role_arn
  }
  depends_on = [
    aws_s3_bucket.tableflow_byob_bucket,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_service_account.app-manager,
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_role_binding.stream-governance-app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin,
    confluent_service_account.app-reader,
    aws_iam_policy.glue_tableflow_access_policy,
    aws_iam_role.glue_tableflow_access_role,
    aws_iam_role_policy_attachment.glue_role_policy_attachment
  ]
}

module "s3_access_role" {
  source                           = "./iam_role_module"
  s3_bucket_name                   = aws_s3_bucket.tableflow_byob_bucket.bucket
  provider_integration_role_arn    = confluent_provider_integration.main.aws[0].iam_role_arn
  provider_integration_external_id = confluent_provider_integration.main.aws[0].external_id
  customer_role_name               = local.customer_s3_access_role_name
  customer_policy_name             = "${var.project_name}-tableflow-s3-access-policy"
  project_name                     = var.project_name
  depends_on                       = [confluent_environment.confluent_project_env]
}

resource "confluent_service_account" "app-reader" {
  display_name = "${var.project_name}-app-reader"
  description  = "Service account of Iceberg Reader applications or compute engines."
  depends_on   = [confluent_environment.confluent_project_env]
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
      id = confluent_environment.confluent_project_env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-reader-environment-admin,
  ]
}

resource "confluent_role_binding" "app-reader-environment-admin" {
  principal   = "User:${confluent_service_account.app-reader.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
  depends_on  = [confluent_environment.confluent_project_env]
}



locals {
  glue_access_role_name = "${var.project_name}-glue-access-role"
  glue_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.glue_access_role_name}"
}


resource "confluent_provider_integration" "glue_integeration" {
  display_name = "${var.project_name}_tableflow_glue_integration"
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  aws {
    customer_role_arn = local.glue_access_role_arn
  }

  depends_on = [
    confluent_api_key.app-manager-kafka-api-key,
    confluent_api_key.stream_governance_api_key,
    confluent_service_account.app-manager,
    confluent_role_binding.stream-governance-app-manager,
    confluent_role_binding.stream-governance-app-manager-environment-admin
  ]
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_environment.confluent_project_env.resource_name}/provider-integration=${confluent_provider_integration.glue_integeration.id}"
}

resource "confluent_catalog_integration" "glue_tableflow_catalog_integeration" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name = "glue_tableflow_catalog_integeration"
  aws_glue {
    provider_integration_id = confluent_provider_integration.glue_integeration.id
  }
  credentials {
    key    = confluent_api_key.app-reader-tableflow-api-key.id
    secret = confluent_api_key.app-reader-tableflow-api-key.secret
  }

  depends_on = [confluent_role_binding.app-manager-provider-integration-resource-owner]
}


resource "aws_iam_role" "glue_tableflow_access_role" {
  name        = local.glue_access_role_name
  description = "IAM role for accessing glue with a trust policy for Tableflow"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = confluent_provider_integration.glue_integeration.aws[0].iam_role_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = confluent_provider_integration.glue_integeration.aws[0].external_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = confluent_provider_integration.glue_integeration.aws[0].iam_role_arn
        }
        Action = "sts:TagSession"
      }
    ]
  })
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration
  ]
}


resource "aws_iam_policy" "glue_tableflow_access_policy" {
  name        = "${var.project_name}-glue-access-policy"
  description = "IAM policy for accessing glue for Tableflow"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "glue:GetTable",
            "glue:GetDatabase",
            "glue:DeleteTable",
            "glue:DeleteDatabase",
            "glue:CreateTable",
            "glue:CreateDatabase",
            "glue:UpdateTable",
            "glue:UpdateDatabase"
          ],
          "Resource" : [
            "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          ]
        }
      ]
    }
  )
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration
  ]
}

resource "aws_iam_role_policy_attachment" "glue_role_policy_attachment" {
  role       = aws_iam_role.glue_tableflow_access_role.name
  policy_arn = aws_iam_policy.glue_tableflow_access_policy.arn
  depends_on = [
    aws_iam_policy.glue_tableflow_access_policy,
    aws_iam_role.glue_tableflow_access_role
  ]
}



resource "confluent_tableflow_topic" "account_daily_ledger" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name  = "account_daily_ledger"
  table_formats = ["ICEBERG"]
  byob_aws {
    bucket_name             = aws_s3_bucket.tableflow_byob_bucket.bucket
    provider_integration_id = confluent_provider_integration.main.id
  }
  credentials {
    key    = confluent_api_key.app-reader-tableflow-api-key.id
    secret = confluent_api_key.app-reader-tableflow-api-key.secret
  }
  depends_on = [confluent_flink_statement.insert_account_daily_ledger_query]
}

resource "confluent_rtce_topic" "account_daily_ledger" {
  cloud       = "AWS"
  description = "account_daily_ledger for real-time analytics"
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  region     = var.aws_region
  topic_name = "account_daily_ledger"
  depends_on = [confluent_flink_statement.insert_account_daily_ledger_query]
}


resource "confluent_api_key" "app-manager-global-api-key" {
  display_name = "${var.project_name}-appmanager-global-api-key"
  description  = "Global API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = "global"
    api_version = "global/v1"
    kind        = "Global"
  }

  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,
  ]
}

# Fetch the active organization
data "confluent_organization" "current" {}

locals {
  rtce_key_base64_auth = base64encode("${confluent_api_key.app-manager-global-api-key.id}:${confluent_api_key.app-manager-global-api-key.secret}")
}

resource "local_file" "ibm_bob_mcp" {
  filename = "${path.module}/ibm-bob-mcp.json"

  content = jsonencode({
    "mcpServers" : {
      "confluent-rtce" : {
        "type" : "streamable-http",
        "url" : "https://mcp.${var.aws_region}.aws.confluent.cloud/mcp/v1/context-engine/organizations/${data.confluent_organization.current.id}/environments/${confluent_environment.confluent_project_env.id}/kafka-clusters/${confluent_kafka_cluster.basic.id}",
        "headers" : {
          "Authorization" : "Basic ${local.rtce_key_base64_auth}"
        }
      }
    }
  })
  depends_on = [confluent_rtce_topic.account_daily_ledger]
}