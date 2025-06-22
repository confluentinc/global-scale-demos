variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}
variable "aws_region" {
  description = "The AWS region where the S3 bucket is located."
  type        = string
}

variable "project_name" {
  description = "Custom Project Name"
  type        = string
}

variable "snowflake_organization_name" {
  description = "Snowflake Organization Name"
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake Account Name"
  type        = string
}

variable "snowflake_username" {
  description = "Snowflake User Name"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake Password"
  type        = string
}

variable "snowflake_role" {
  description = "Snowflake User Role"
  type        = string
}

variable "hardware" {
description = "Base Hardware Archietecture"
}

variable "tableflow_reader_api_key_id" {
  type = string
}

variable "tableflow_reader_api_key_secret" {
  type = string
}

variable "env_id" {
    type = string
}

variable "kafka_id" {
    type = string
}

variable "confluent_rest_catalog_uri" {
    type = string
}


variable "tableflow_s3_bucket" {
    type = string
} 

variable "tableflow_s3_bucket_arn" {
    type = string
} 