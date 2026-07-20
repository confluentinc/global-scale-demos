variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API key (Cloud resource management scope) used by the Terraform provider to create environments, clusters, service accounts, etc."
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API secret (Cloud resource management scope) paired with confluent_cloud_api_key."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Unique identifier used as a prefix for every resource's display name (environment, cluster, service account, API keys, compute pool) so multiple deployments of this project don't collide within the same org."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, start with a letter, and be 3-32 characters."
  }
}

variable "cloud" {
  description = "Cloud provider for the Kafka cluster and Flink compute pool."
  type        = string
  default     = "AWS"
}

variable "region" {
  description = "Cloud region for the Kafka cluster and Flink compute pool."
  type        = string
  default     = "ap-south-1"
}

variable "flink_max_cfu" {
  description = "Max Confluent Flink Units (CFUs) for the Flink compute pool."
  type        = number
  default     = 10
}

variable "run_producer_container" {
  description = "Whether Terraform should also build and run the data-generator producer as a Docker container. Set to false if you'd rather run python-producer.py yourself (e.g. locally, for faster iteration)."
  type        = bool
  default     = true
}

variable "live_map_port" {
  description = "Host port the live-map web UI is published on (http://localhost:<this port>)."
  type        = number
  default     = 8765
}

variable "train_headway_seconds" {
  description = "Real gap (seconds) between two consecutive trains on the same line + direction. Passed straight to the producer container. See python-producer.py for what this actually controls."
  type        = number
  default     = 600
}

variable "producer_time_scale" {
  description = "Producer TIME_SCALE -- multiplies every sleep for local smoke-testing. Leave at 1.0 for a true real-time run; do not ship any other value."
  type        = number
  default     = 1.0
}

variable "enable_surge_detection" {
  description = "Whether to deploy the Phase 2 surge-detection pipeline (ML_DETECT_ANOMALIES over per-line/direction headcount, plus an AWS Bedrock model that turns a detected surge into a dispatch recommendation). Requires bedrock_aws_access_key/bedrock_aws_secret_key. Defaults to false so existing deployments aren't affected until you opt in."
  type        = bool
  default     = false
}

variable "bedrock_aws_access_key" {
  description = "AWS access key with bedrock:InvokeModel permission, used only by the Flink Bedrock connection (surge-detection.tf). Required if enable_surge_detection is true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_aws_secret_key" {
  description = "AWS secret key paired with bedrock_aws_access_key."
  type        = string
  sensitive   = true
  default     = ""
}

variable "bedrock_model_endpoint" {
  description = "Full AWS Bedrock invoke URL for the text-generation model used to turn a detected surge into a dispatch recommendation, e.g. https://bedrock-runtime.<region>.amazonaws.com/model/<model-id>/invoke."
  type        = string
  default     = "https://bedrock-runtime.us-east-1.amazonaws.com/model/us.anthropic.claude-sonnet-4-5-20250929-v1:0/invoke"
}
