terraform {
  required_version = ">= 1.5.0"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.78.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.5.0"
    }
  }
}
