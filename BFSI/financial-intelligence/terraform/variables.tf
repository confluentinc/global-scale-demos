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

variable "postgres_database_port" {
  description = "Postgres DB port"
  type        = string
  default = "5432"
}

variable "postgres_database_username" {
  description = "Postgres DB username"
  type        = string
  default = "postgres"
}

variable "postgres_database_password" {
  description = "Postgres DB password"
  type        = string
  default = "postgres"
}

variable "postgres_database_hostname" {
  description = "Postgres DB hostname"
  type        = string
  default     = "localhost"
}

variable "postgres_database_name" {
  description = "Postgres DB name"
  type        = string
  default     = "postgres"
}