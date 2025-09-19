# Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    confluent = { 
      source  = "confluentinc/confluent"
      version = "2.35.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  } 

  required_version = ">= 1.0"
} 
