variable "aws_region" {
  description = "The AWS region where the S3 bucket is located."
  type        = string
}

variable "project_name" {
  description = "Custom Project Name"
  type        = string
}

variable "tableflow_s3_bucket" {
    type = string
} 

variable "databricks_ui_user" {
     type = string
}
