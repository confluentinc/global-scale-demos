terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.17.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.31.0"
    }
    snowflake = {
      source = "snowflakedb/snowflake"
      version = "2.1.0"
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

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "aws" {
  region = var.aws_region
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_username
  password          = var.snowflake_password
  role              = var.snowflake_role
  preview_features_enabled = ["snowflake_external_volume_resource"]
}

module "oltp" {
  count = var.enable_oltp ? 1:0
  source                          = "./oltp"
  aws_region                      = var.aws_region  
  hardware                        = var.hardware
  project_name                    = var.project_name 
  mysql_database_username         = var.mysql_database_username
  mysql_database_password         = var.mysql_database_password
  mysql_database_port             = var.mysql_database_port
  confluent_cloud_api_key         = var.confluent_cloud_api_key
  confluent_cloud_api_secret      = var.confluent_cloud_api_secret

  providers = {
    aws       = aws
    confluent = confluent
  }
}

module "olap_snowflake" {
  count = var.enable_olap_snowflake ? 1:0
  source                          = "./olap_snowflake"
  aws_region                      = var.aws_region  
  project_name                    = var.project_name 
  confluent_cloud_api_key         = var.confluent_cloud_api_key
  confluent_cloud_api_secret      = var.confluent_cloud_api_secret
  snowflake_organization_name     = var.snowflake_organization_name
  snowflake_account_name          = var.snowflake_account_name
  snowflake_username              = var.snowflake_username
  snowflake_password              = var.snowflake_password
  snowflake_role                  = var.snowflake_role
  hardware                        = var.hardware
  tableflow_reader_api_key_id     = module.oltp[0].tableflow_reader_api_key_id
  tableflow_reader_api_key_secret = module.oltp[0].tableflow_reader_api_key_secret
  env_id                          = module.oltp[0].env_id
  kafka_id                        = module.oltp[0].kafka_id
  confluent_rest_catalog_uri      = module.oltp[0].confluent_rest_catalog_uri
  tableflow_s3_bucket             = module.oltp[0].tableflow_s3_bucket
  tableflow_s3_bucket_arn         = module.oltp[0].tableflow_s3_bucket_arn

  providers = {
    aws       = aws
    confluent = confluent
    snowflake=snowflake
  }
}