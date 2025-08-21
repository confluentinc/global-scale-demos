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



variable "tableflow_admin_api_key_id" {
  type = string
}

variable "tableflow_admin_api_key_secret" {
  type = string
}

variable "app_manager_user_id" {
    type= string
}


variable "env_id" {
    type = string
}

variable "env_resource_name" {
    type = string
}

variable "kafka_id" {
    type = string
}



variable "tableflow_s3_bucket" {
    type = string
} 

variable "tableflow_s3_bucket_arn" {
    type = string
} 