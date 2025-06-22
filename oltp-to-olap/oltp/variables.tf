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

variable "hardware" {
description = "Base Hardware Archietecture"
}