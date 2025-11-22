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
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.17.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "confluent" {

  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "postgresql" {
  host            = aws_db_instance.postgres_db.address
  port            = aws_db_instance.postgres_db.port
  database        = var.postgres_db_name
  username        = var.postgres_user
  password        = var.postgres_password
  sslmode         = var.postgres_sslmode
}

provider "aws" {
  region = var.cloud_region
}
