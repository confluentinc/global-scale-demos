resource "confluent_environment" "confluent_project_env" {
  display_name = "${var.project_name}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
  depends_on = [ aws_db_parameter_group.postgres_debezium_parameter_group ] 
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.confluent_project_env.id
  }

  depends_on = [
    confluent_kafka_cluster.main
  ]
}

data "confluent_organization" "main" {}
resource "confluent_kafka_cluster" "main" {
  display_name = "${var.project_name}-kafka-cluster"
  availability = var.kafka_availability   # e.g., "SINGLE_ZONE"
  cloud        = var.cloud_provider       # "AWS" | "GCP" | "AZURE"
  region       = var.cloud_region

  standard {}  # change to standard {}, enterprise {}, dedicated {} per your plan

  environment {
    id = confluent_environment.confluent_project_env.id
  }
}

data "confluent_flink_region" "flink-region" {
  cloud   = var.cloud_provider
  region  = var.cloud_region
}

resource "confluent_flink_compute_pool" "pool" {
  display_name = var.flink_pool_name
  cloud        = var.cloud_provider
  region       = var.cloud_region
  max_cfu      = var.flink_max_cfu

  environment {
    id =  confluent_environment.confluent_project_env.id
  }
}