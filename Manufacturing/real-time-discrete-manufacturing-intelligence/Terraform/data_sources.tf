data "confluent_organization" "org" {}

data "confluent_environment" "target" {
  id = var.environment_id
}
data "confluent_flink_region" "region" {
  cloud  = var.cloud_provider
  region = var.cloud_region
}

data "confluent_schema_registry_cluster" "env" {
  environment {
    id = data.confluent_environment.target.id
  }
}