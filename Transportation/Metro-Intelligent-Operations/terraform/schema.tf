# Registers the JSON schema for the raw topic's value *before* the Flink
# statements run. This is the fix for a real bug: Confluent Cloud Flink infers
# a Kafka topic's table columns from its registered Schema Registry schema --
# if nothing is registered yet (e.g. the producer container hasn't produced
# its first message), `CREATE TABLE ... AS SELECT` fails validation with
# "Table 'metadata' not found", because Flink has no idea the topic's JSON
# has a `metadata` field at all. Registering it here, as real infrastructure,
# removes the implicit runtime-ordering dependency on the producer.
resource "confluent_schema" "camera_events_value" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.essentials.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.essentials.rest_endpoint
  subject_name  = "${confluent_kafka_topic.camera_events.topic_name}-value"
  format        = "JSON"
  schema        = file("${path.module}/../producer/schemas/metro-camera-events-value.json")

  credentials {
    key    = confluent_api_key.app_manager_sr_api_key.id
    secret = confluent_api_key.app_manager_sr_api_key.secret
  }
}
