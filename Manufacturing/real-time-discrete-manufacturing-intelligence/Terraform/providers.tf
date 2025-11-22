terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = ">= 2.2.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }
}

provider "confluent" {

  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "postgresql" {
  host            = var.postgres_host
  port            = var.postgres_port
  database        = var.postgres_db_name
  username        = var.postgres_user
  password        = var.postgres_password
  sslmode         = var.postgres_sslmode
}