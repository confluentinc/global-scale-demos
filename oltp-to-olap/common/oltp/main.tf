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


resource "aws_db_parameter_group" "mysql_debezium_parameter_group" {
  name   = replace("${var.project_name}-mysql-parameter-group", "_", "-")
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
  identifier                          = replace("${var.project_name}-mysql","_","-")
  allocated_storage                   = 10
  engine                              = "mysql"
  engine_version                      = "8.0.41"
  instance_class                      = "db.t3.micro"
  port                                = "${var.mysql_database_port}"
  username                            = "${var.mysql_database_username}"
  password                            = "passw0rd"
  parameter_group_name                = aws_db_parameter_group.mysql_debezium_parameter_group.name
  skip_final_snapshot                 = true
  deletion_protection                 = false
  publicly_accessible                 = true
  vpc_security_group_ids              = [aws_security_group.instance.id]
  storage_encrypted                   = true
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

resource "docker_image" "tools_image" {
  name = "demotools:${var.project_name}"
  build {
    context    = "../common/oltp/tools"
    dockerfile = "Dockerfile"
    build_args = {
      HARDWARE = var.hardware
    }
  }
  depends_on = [ aws_db_parameter_group.mysql_debezium_parameter_group ]
}

resource "docker_container" "tools_container" {
  name     = "${var.project_name}-tools"
  image    = docker_image.tools_image.name
  start    = true
  must_run = true
  
  depends_on = [
    aws_db_instance.mysql_db,
    docker_image.tools_image
  ]

    command = [
   "sleep",
   "infinity"
  ]
}

resource "null_resource" "run_mysql_initial" {
  
  provisioner "local-exec" {
    command = <<EOT
      docker cp ../common/oltp/mysql-initial.sql ${var.project_name}-tools:/tmp/mysql-initial.sql
      docker exec ${var.project_name}-tools bash -c "mysql -h ${aws_db_instance.mysql_db.address} -P ${aws_db_instance.mysql_db.port} -u ${aws_db_instance.mysql_db.username} -p${var.mysql_database_password} < /tmp/mysql-initial.sql"
    EOT
  }

  depends_on = [docker_container.tools_container]
}

resource "docker_image" "products_generator_image" {
  name = "generate:products-${var.project_name}"
  build {
    context = "../common/oltp/products_generator"
    dockerfile = "Dockerfile"
  }
  depends_on = [ aws_db_parameter_group.mysql_debezium_parameter_group ] 
}

resource "docker_container" "products_generator_container" {
  name  = "${var.project_name}-products-generator"
  image = docker_image.products_generator_image.name
  
  env = [
    "DB_HOST=${aws_db_instance.mysql_db.address}",
    "DB_USER=${aws_db_instance.mysql_db.username}",
    "DB_PASSWORD=${aws_db_instance.mysql_db.password}",
    "DB_NAME=source"
  ]
  start      = true
  restart    = "on-failure"
  must_run   = true
  depends_on = [null_resource.run_mysql_initial]
}

resource "confluent_environment" "confluent_project_env" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
  depends_on = [ aws_db_parameter_group.mysql_debezium_parameter_group ] 
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
  depends_on = [ confluent_environment.confluent_project_env ]
  
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
  depends_on  = [ confluent_environment.confluent_project_env ]
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
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
  depends_on = [ confluent_environment.confluent_project_env ]
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
  depends_on = [ confluent_environment.confluent_project_env ]
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
  table_formats = ["ICEBERG", "DELTA"]
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
    confluent_connector.mysql,
    confluent_flink_statement.low_stock_alert_statement,

  ]
}

locals {
  tags = {
    PII      = "PII tag"
    Warehouse = "Warehouse tag"
    OLTP = "OLTP tag"
    OLAP = "OLAP tag"
  }
}

resource "confluent_tag" "this" {
  for_each = local.tags

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }

  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint

  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  name        = each.key
  description = each.value
}


locals {
  tag_bindings = {
    pii_customers = {
      tag_name    = "PII"
      entity_name = "mysql.source.customers"
    }
    warehouse_products = {
      tag_name    = "Warehouse"
      entity_name = "mysql.source.products"
    }
    olap_stocks = {
      tag_name    = "OLAP"
      entity_name = "low_stock_alerts"
    }
    oltp_customers = {
      tag_name    = "OLTP"
      entity_name = "mysql.source.customers"
    }
    oltp_products = {
      tag_name    = "OLTP"
      entity_name = "mysql.source.products"
    }
    oltp_stocks = {
      tag_name    = "OLTP"
      entity_name = "low_stock_alerts"
    }
  }
}

resource "confluent_tag_binding" "this" {
  for_each = local.tag_bindings

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }

  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint

  credentials {
    key    = confluent_api_key.stream_governance_api_key.id
    secret = confluent_api_key.stream_governance_api_key.secret
  }

  tag_name = confluent_tag.this[each.value.tag_name].name

  entity_name = "${data.confluent_schema_registry_cluster.essentials.id}:${confluent_kafka_cluster.basic.id}:${each.value.entity_name}"

  entity_type = "kafka_topic"

  depends_on = [
    confluent_flink_statement.low_stock_alert_statement,
    confluent_tag.this
  ]
}

data "aws_caller_identity" "current" {}

locals {
  customer_s3_access_role_name = "${var.project_name}-tableflow-access-role"
  customer_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_s3_access_role_name}"
  
}

resource "aws_s3_bucket" "tableflow_byob_bucket" {
  bucket = replace("${var.project_name}-s3-bucket","_","-")
  tags = {
    Name        = "Tableflow Demo S3 Bucket"
  }
  force_destroy = true
  depends_on = [ confluent_environment.confluent_project_env ]
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
  source                           = "../iam_role_module"
  s3_bucket_name                   = aws_s3_bucket.tableflow_byob_bucket.bucket
  provider_integration_role_arn    = confluent_provider_integration.main.aws[0].iam_role_arn
  provider_integration_external_id = confluent_provider_integration.main.aws[0].external_id
  customer_role_name               = local.customer_s3_access_role_name
  customer_policy_name             = "${var.project_name}-tableflow-s3-access-policy"
  project_name=var.project_name
  depends_on = [ confluent_environment.confluent_project_env ]
}


data "confluent_organization" "main" {}

resource "confluent_service_account" "app-reader" {
  display_name = "${var.project_name}-app-reader"
  description  = "Service account of Iceberg Reader applications or compute engines."
  depends_on = [ confluent_environment.confluent_project_env ]
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
  depends_on = [ confluent_environment.confluent_project_env ]
}
