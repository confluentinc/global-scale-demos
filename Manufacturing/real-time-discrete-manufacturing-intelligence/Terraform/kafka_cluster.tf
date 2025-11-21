resource "confluent_kafka_cluster" "main" {
  display_name = var.kafka_cluster_name
  availability = var.kafka_availability   # e.g., "SINGLE_ZONE"
  cloud        = var.cloud_provider       # "AWS" | "GCP" | "AZURE"
  region       = var.cloud_region

  standard {}  # change to standard {}, enterprise {}, dedicated {} per your plan

  environment {
    id = data.confluent_environment.target.id
  }

}



# New topic Creation

resource "confluent_kafka_topic" "work_orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  topic_name         = "mf.public.work_orders"
  partitions_count   = 1
  credentials {
    key = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}


# New topic Creation

resource "confluent_kafka_topic" "sensor_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  topic_name         = "mf.public.sensor_events"
  partitions_count   = 1
  credentials {
    key = confluent_api_key.kafka_admin.id
    secret = confluent_api_key.kafka_admin.secret
  }
  depends_on = [confluent_role_binding.connect_sa_cluster_admin]
}

