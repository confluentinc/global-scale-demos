terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.17.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.31.0"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "aws" {
  region = var.aws_region
}

resource "aws_db_parameter_group" "mysql_debezium_parameter_group" {
  name   = "${var.project_name}-mysql-parameter-group"
  family = "mysql8.0"

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  parameter {
    name  = "binlog_row_image"
    value = "full"
  }
}

resource "aws_db_instance" "mysql_db" {
  identifier             = "${var.project_name}-mysql"
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "8.0.41"
  instance_class         = "db.t3.micro"
  port                   = "${var.mysql_database_port}"
  username               = "${var.mysql_database_username}"
  password               = "passw0rd"
  parameter_group_name   = aws_db_parameter_group.mysql_debezium_parameter_group.name
  skip_final_snapshot    = true
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.instance.id]
  storage_encrypted      = true
  backup_retention_period             = 3
  iam_database_authentication_enabled = true
  depends_on = [
    aws_db_parameter_group.mysql_debezium_parameter_group
  ]
}

resource "aws_security_group" "instance" {
  name = "${var.project_name}-sg"
  ingress {
    from_port   = "${var.mysql_database_port}"
    to_port     = "${var.mysql_database_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "docker_container" "mysql" {
  image             = "mysql:latest"
  name              = "mysql-test-container"
  must_run          = true
  command = [
   "sleep",
   "infinity"
  ]
   depends_on = [
    aws_db_instance.mysql_db
  ]
}

resource "null_resource" "run_mysql_initial" {
  
  provisioner "local-exec" {
    command = <<EOT
      docker cp mysql-initial.sql mysql-test-container:/tmp/mysql-initial.sql
      docker exec mysql-test-container bash -c "mysql -h ${aws_db_instance.mysql_db.address} -P ${aws_db_instance.mysql_db.port} -u ${aws_db_instance.mysql_db.username} -p${var.mysql_database_password} < /tmp/mysql-initial.sql"
    EOT
  }

  depends_on = [docker_container.mysql]
}

resource "docker_image" "products_generator_image" {
  name = "generate:products"
  build {
    context = "./products_generator"
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "products_generator_container" {
  name  = "products-generator"
  image = docker_image.products_generator_image.name
  
  env = [
    "DB_HOST=${aws_db_instance.mysql_db.address}",
    "DB_USER=${aws_db_instance.mysql_db.username}",
    "DB_PASSWORD=${aws_db_instance.mysql_db.password}",
    "DB_NAME=source"
  ]
  start = true
  restart = "on-failure"
  must_run = true
  depends_on = [null_resource.run_mysql_initial]
}

resource "confluent_environment" "confluent_project_env" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
}


resource "confluent_kafka_cluster" "basic" {
  display_name = "${var.project_name}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  // S3 buckets must be in the same region as the cluster
  region = var.aws_region
  basic {}
  environment {
    id = confluent_environment.confluent_project_env.id
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic
  ]
}

// 'app-manager' service account is required in this configuration to create 'purchase' topic and grant ACLs
// to 'app-producer' and 'app-consumer' service accounts.
resource "confluent_service_account" "app-manager" {
  display_name = "${var.project_name}-app-manager"
  description  = "Service account to manage 'inventory' Kafka cluster"
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal = "User:${confluent_service_account.app-manager.id}"
  role_name = "ResourceOwner"
  // TODO: add resource_name attribute to confluent_provider_integration
  crn_pattern = "${confluent_environment.confluent_project_env.resource_name}/provider-integration=${confluent_provider_integration.main.id}"

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

  # The goal is to ensure that confluent_role_binding.app-manager-kafka-cluster-admin is created before
  # confluent_api_key.app-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
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
    id          = data.confluent_schema_registry_cluster.essentials.id
    api_version = data.confluent_schema_registry_cluster.essentials.api_version
    kind        = data.confluent_schema_registry_cluster.essentials.kind

    environment {
      id = confluent_environment.confluent_project_env.id
    }
  }
}




resource "confluent_service_account" "app-connector" {
  display_name = "${var.project_name}-app-connector567"
  description  = "Service account of S3 Sink Connector to consume from 'stock-trades' topic of 'inventory' Kafka cluster"
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





resource "confluent_connector" "mysql" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {
    "database.password"        = "${var.mysql_database_password}"
  }

  config_nonsensitive = {
    "connector.class"          = "MySqlCdcSourceV2"
    "name"                     = "${var.project_name}-mysql-source-connector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "tasks.max"                = "1"
    "database.hostname"        = aws_db_instance.mysql_db.address
    "database.include.list"    = "source"
    "database.port"            = aws_db_instance.mysql_db.port
    "database.user"            = aws_db_instance.mysql_db.username
    "output.data.format"       = "AVRO"
    "output.key.format"        = "AVRO"
    "topic.prefix"             = "mysql"
    "snapshot.mode"            = "when_needed"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic,
    null_resource.run_mysql_initial,
  ]
}



resource "confluent_flink_compute_pool" "main" {
  display_name     = "${var.project_name}-flink-pool"
  cloud        = "AWS"
  region = var.aws_region
  max_cfu          = 10
  environment {
    id = confluent_environment.confluent_project_env.id
  }
}

data "confluent_flink_region" "flink-region" {
  cloud   = "AWS"
  region  = var.aws_region
}

resource "confluent_role_binding" "app-manager-flink-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
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

resource "confluent_flink_statement" "customers_changelog_mode_statement" {
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
  statement  = "ALTER TABLE `mysql.source.customers` SET ('changelog.mode' = 'append');"
  properties = {
    "sql.current-catalog"  = confluent_environment.confluent_project_env.display_name
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
    confluent_connector.mysql,
  ]
}

resource "confluent_flink_statement" "customers_value_format_statement" {
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
  statement  = "ALTER TABLE `mysql.source.customers` SET ('value.format' = 'avro-registry');"
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
    confluent_connector.mysql,
    confluent_flink_statement.customers_changelog_mode_statement,
  ]
}




resource "confluent_flink_statement" "products_changelog_mode_statement" {
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
  statement  = "ALTER TABLE `mysql.source.products` SET ('changelog.mode' = 'append');"
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
    confluent_connector.mysql,
  ]
}

resource "confluent_flink_statement" "products_value_format_statement" {
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
  statement  = "ALTER TABLE `mysql.source.products` SET ('value.format' = 'avro-registry')"
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
    confluent_connector.mysql,
    confluent_flink_statement.products_changelog_mode_statement,
  ]
}

resource "confluent_flink_statement" "low_stock_alert_statement" {
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
  statement  = "CREATE TABLE low_stock_alerts DISTRIBUTED BY HASH(product_id) INTO 3 BUCKETS WITH ('changelog.mode' = 'append') AS SELECT after.product_id,after.product_name,after.quantity,'Low stock: Quantity below 50!' AS alert_message FROM `mysql.source.products`  WHERE after.`quantity` <50;"
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
    confluent_connector.mysql,
    confluent_flink_statement.products_value_format_statement,
  ]
}



resource "confluent_api_key" "app-manager-tableflow-api-key" {
  display_name = "${var.project_name}-app-manager-tableflow-api-key"
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
      id = confluent_environment.confluent_project_env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-provider-integration-resource-owner,
  ]
}


resource "confluent_tableflow_topic" "final-tableflow-topic" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  display_name = "low_stock_alerts"

  // Use BYOB AWS storage
  byob_aws {
    bucket_name             = "${var.project_name}-s3-bucket"
    provider_integration_id = confluent_provider_integration.main.id
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }

  # The goal is to ensure that confluent_schema.purchase is created before
  # an instance of confluent_tableflow_topic is created since it requires
  # a topic with a schema. The provider integration and IAM Roles also have
  # to be set up before an instance of confluent_tableflow_topic is created.


  depends_on = [
    module.s3_access_role,
    # To avoid "Schemaless topic detected for topic stock-trades. Schemaless topics are not supported. Please specify a value schema." error
    confluent_connector.mysql,
    confluent_flink_statement.low_stock_alert_statement,

  ]
}


resource "confluent_tag" "pii" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name = "PII"
  description = "PII tag"

}

resource "confluent_tag" "warehouse" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name = "Warehouse"
  description = "Warehouse tag"
}

resource "confluent_tag" "oltp" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name = "OLTP"
  description = "OLTP tag"
}

resource "confluent_tag" "olap" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name = "OLAP"
  description = "OLAP tag"

}


resource "confluent_tag_binding" "pii_customers" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.pii.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:mysql.source.customers"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}

resource "confluent_tag_binding" "oltp_customers" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.oltp.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:mysql.source.customers"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}

resource "confluent_tag_binding" "warehouse_products" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.warehouse.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:mysql.source.products"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}


resource "confluent_tag_binding" "oltp_products" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.oltp.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:mysql.source.products"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}

resource "confluent_tag_binding" "olap_stocks" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.olap.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:low_stock_alerts"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}

resource "confluent_tag_binding" "oltp_stocks" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.oltp.name
  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:low_stock_alerts"
  entity_type = "kafka_topic"
  depends_on = [
    confluent_flink_statement.low_stock_alert_statement
   ]
}



data "aws_caller_identity" "current" {}

locals {
  customer_s3_access_role_name = "${var.project_name}_TableflowS3AccessRole"
  customer_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_s3_access_role_name}"
  
}

resource "aws_s3_bucket" "tableflow_byob_bucket" {
  bucket = "${var.project_name}-s3-bucket"
  tags = {
    Name        = "Tableflow Demo S3 Bucket"
  }
  force_destroy = true
}

resource "confluent_provider_integration" "main" {
  display_name = "${var.project_name}_s3_tableflow_integration"
  environment {
    id = confluent_environment.confluent_project_env.id
  }
  aws {
    # During the creation of confluent_provider_integration.main, the S3 role does not yet exist.
    # The role will be created after confluent_provider_integration.main is provisioned
    # by the s3_access_role module using the specified target name.
    # Note: This is a workaround to avoid updating an existing role or creating a circular dependency.
    customer_role_arn = local.customer_s3_access_role_arn
  }
    depends_on = [
    aws_s3_bucket.tableflow_byob_bucket
  ]
}

module "s3_access_role" {
  source                           = "./iam_role_module"
  s3_bucket_name                   = "${var.project_name}-s3-bucket"
  provider_integration_role_arn    = confluent_provider_integration.main.aws[0].iam_role_arn
  provider_integration_external_id = confluent_provider_integration.main.aws[0].external_id
  customer_role_name               = local.customer_s3_access_role_name
  project_name=var.project_name
}


data "confluent_organization" "main" {}

resource "confluent_service_account" "app-reader" {
  display_name = "${var.project_name}-app-reader"
  description  = "Service account of Iceberg Reader applications or compute engines."
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

// https://docs.confluent.io/cloud/current/topics/tableflow/operate/tableflow-rbac.html#access-to-tableflow-resources
resource "confluent_role_binding" "app-reader-environment-admin" {
  principal   = "User:${confluent_service_account.app-reader.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
}



resource "aws_iam_role" "snowflake_s3_access_role" {
  name = "${var.project_name}-snowflake-access-role"
  description = "IAM role for accessing S3 with a trust policy for Snowflake"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${data.aws_caller_identity.current.id}"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
            }
        }
    ]
})
  depends_on = [
    confluent_provider_integration.main,
  ]
}


resource "aws_iam_policy" "snowflake_s3_access_policy" {
  name        = "${var.project_name}-snowflake-access-policy"
  description = "IAM policy for accessing the S3 bucket for Snowflake"

  policy = jsonencode({
   "Version": "2012-10-17",
   "Statement": [
         {
            "Effect": "Allow",
            "Action": [
               "s3:PutObject",
               "s3:GetObject",
               "s3:GetObjectVersion",
               "s3:DeleteObject",
               "s3:DeleteObjectVersion"
            ],
            "Resource": "${aws_s3_bucket.tableflow_byob_bucket.arn}/*"
         },
         {
            "Effect": "Allow",
            "Action": [
               "s3:ListBucket",
               "s3:GetBucketLocation"
            ],
            "Resource": "${aws_s3_bucket.tableflow_byob_bucket.arn}",
            "Condition": {
               "StringLike": {
                     "s3:prefix": [
                        "*"
                     ]
               }
            }
         }
   ]
})
  depends_on = [
    confluent_provider_integration.main,
  ]
}

resource "aws_iam_role_policy_attachment" "snowflake_role_policy_attachment" {
  role       = aws_iam_role.snowflake_s3_access_role.name
  policy_arn = aws_iam_policy.snowflake_s3_access_policy.arn
}

# resource "snowflake_warehouse" "warehouse" {
#   name                                = "${var.project_name}-warehouse"
#   warehouse_size                      = "X-SMALL"
#     depends_on = [
#     confluent_provider_integration.main,
#   ]
# }

# resource "null_resource" "create_snowflake_external_volume" {
#   provisioner "local-exec" {
#     command = <<EOT
#       snow sql \
#         --account ${var.snowflake_account_name} \
#         --user ${var.snowflake_username} \
#         --password ${var.snowflake_password} \
#         --role ${var.snowflake_role} \
#         -x -q "CREATE OR REPLACE EXTERNAL VOLUME \"sahil_new_external_volume\" STORAGE_LOCATIONS = (( NAME = '${var.project_name}-s3-${var.aws_region}' STORAGE_PROVIDER = 'S3' STORAGE_BASE_URL = 's3://${aws_s3_bucket.tableflow_byob_bucket.bucket}/' STORAGE_AWS_ROLE_ARN = '${aws_iam_role.snowflake_s3_access_role.arn}' STORAGE_AWS_EXTERNAL_ID = 'new_client' )) ALLOW_WRITES = TRUE;"
#     EOT
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.snowflake_role_policy_attachment
#   ]
# }

# resource "null_resource" "update_snowflake_iam_role_trust_policy" {
  
#   provisioner "local-exec" {
#     command = <<EOT
#       export AWS_REGION="${var.aws_region}"
#       aws iam update-assume-role-policy \
#   --role-name ${aws_iam_role.snowflake_s3_access_role.name} \
#   --policy-document '{
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Principal": {
#                 "AWS": "${jsondecode(snowflake_external_volume.tableflow_s3.describe_output[1].value).STORAGE_AWS_IAM_USER_ARN}"
#             },
#             "Action": "sts:AssumeRole",
#             "Condition": {
#             }
#         }
#     ]
# }'
#     EOT
#   }

#   depends_on = [snowflake_external_volume.tableflow_s3]
# }
