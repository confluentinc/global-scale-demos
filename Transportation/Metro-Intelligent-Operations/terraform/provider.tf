provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Talks to the local Docker daemon (Docker Desktop / dockerd) that `terraform
# apply` runs on. No credentials needed for a local daemon.
provider "docker" {}
