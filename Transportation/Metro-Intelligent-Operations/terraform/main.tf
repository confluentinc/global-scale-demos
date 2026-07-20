data "confluent_organization" "main" {}

resource "confluent_environment" "this" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

resource "confluent_kafka_cluster" "this" {
  display_name = "${var.project_name}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = var.cloud
  region       = var.region
  basic {}

  environment {
    id = confluent_environment.this.id
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.this.id
  }

  depends_on = [
    confluent_kafka_cluster.this
  ]
}

data "confluent_flink_region" "this" {
  cloud  = var.cloud
  region = var.region
}
