resource "confluent_kafka_topic" "camera_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.this.id
  }
  topic_name       = "metro-camera-events"
  partitions_count = 1
  rest_endpoint    = confluent_kafka_cluster.this.rest_endpoint

  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}
