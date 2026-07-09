terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.36.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.63.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}