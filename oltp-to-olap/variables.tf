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

variable "mysql_database_port" {
  description = "MySql DB port"
  type        = string
}

variable "mysql_database_username" {
  description = "MySql DB username"
  type        = string
}


variable "mysql_database_password" {
  description = "MySql DB password"
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