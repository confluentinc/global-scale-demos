# Builds and runs the two application containers using the exact same
# credentials/endpoints Terraform just provisioned above -- no manual copying
# of API keys into a .env file needed for this deployment path.
#
# Build context for both images is the repo root (one level up from this
# terraform/ directory), because both producer/python-producer.py and
# live-map/server.py reuse the shared ../metro_network.py at runtime, and
# each Dockerfile needs to COPY it in from outside its own app directory.

locals {
  repo_root                = abspath("${path.module}/..")
  kafka_bootstrap_no_proto = trimprefix(confluent_kafka_cluster.this.bootstrap_endpoint, "SASL_SSL://")
}

resource "docker_image" "producer" {
  name = "${var.project_name}-producer:latest"

  build {
    context    = local.repo_root
    dockerfile = "producer/Dockerfile"
  }
}

resource "docker_container" "producer" {
  count   = var.run_producer_container ? 1 : 0
  name    = "${var.project_name}-producer"
  image   = docker_image.producer.image_id
  restart = "unless-stopped"

  env = [
    "BOOTSTRAP_SERVER=${local.kafka_bootstrap_no_proto}",
    "KAFKA_API_KEY=${confluent_api_key.app_manager_kafka_api_key.id}",
    "KAFKA_API_SECRET=${confluent_api_key.app_manager_kafka_api_key.secret}",
    "TOPIC=${confluent_kafka_topic.camera_events.topic_name}",
    "SCHEMA_REGISTRY_URL=${data.confluent_schema_registry_cluster.essentials.rest_endpoint}",
    "SCHEMA_REGISTRY_API_KEY=${confluent_api_key.app_manager_sr_api_key.id}",
    "SCHEMA_REGISTRY_API_SECRET=${confluent_api_key.app_manager_sr_api_key.secret}",
    "TRAIN_HEADWAY_SECONDS=${var.train_headway_seconds}",
    "TIME_SCALE=${var.producer_time_scale}",
    "ENABLE_SURGE_INJECTION=${var.enable_surge_detection}",
  ]

  depends_on = [
    confluent_flink_statement.train_departure_totals,
  ]
}

resource "docker_image" "live_map" {
  name = "${var.project_name}-live-map:latest"

  build {
    context    = local.repo_root
    dockerfile = "live-map/Dockerfile"
  }
}

resource "docker_container" "live_map" {
  name    = "${var.project_name}-live-map"
  image   = docker_image.live_map.image_id
  restart = "unless-stopped"

  ports {
    internal = 8765
    external = var.live_map_port
    protocol = "tcp"
  }

  # live-map/server.py only needs Kafka access (see its module docstring for
  # why it doesn't need Schema Registry credentials at all -- that includes
  # the surge-highlight topic below, which is deliberately JSON-registry
  # encoded for exactly this reason).
  env = [
    "BOOTSTRAP_SERVER=${local.kafka_bootstrap_no_proto}",
    "KAFKA_API_KEY=${confluent_api_key.app_manager_kafka_api_key.id}",
    "KAFKA_API_SECRET=${confluent_api_key.app_manager_kafka_api_key.secret}",
    "TOPIC=${confluent_kafka_topic.camera_events.topic_name}",
    "ENABLE_SURGE_HIGHLIGHTS=${var.enable_surge_detection}",
  ]

  depends_on = [
    confluent_flink_statement.train_departure_totals,
  ]
}
