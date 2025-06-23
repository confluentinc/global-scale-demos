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
  default = "3306"
}

variable "mysql_database_username" {
  description = "MySql DB username"
  type        = string
  default = "mysqladmin"
}


variable "mysql_database_password" {
  description = "MySql DB password"
  type        = string
  default = "passw0rd"
}

variable "databricks_host" {
  description = "Databricks Host URL"
  type        = string
  default     = ""

}

variable "databricks_client_id" {
  description = "Databricks Service Principal Client ID"
  type        = string
  default     = ""

}

variable "databricks_client_secret" {
  description = "Databricks Service Principal Client Secret"
  type        = string
  default     = ""
}

variable "databricks_ui_user" {
  description = "Databricks UI User"
  type        = string
  default     = ""
}

variable "hardware" {
description = "Base Hardware Archietecture"
}

variable "enable_oltp" {
  description = "Create oltp specific resources"
  default = true
}

variable "enable_olap_glue" {
  description = "Create olap_glue specific resources"
  default = false
}

variable "enable_olap_databricks" {
  description = "Create olap_databricks specific resources"
  default = false
}