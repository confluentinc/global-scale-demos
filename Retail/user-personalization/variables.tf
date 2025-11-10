# --- General Confluent Cloud Variables ---
variable "access_key" {
  description = "AWS access key"
  type        = string
  default     = "" # Set to empty if using profiles/roles
}
variable "secret_key" {
       description = "AWS secret key"
          type        = string
  sensitive   = true
  default     = "" # Set to empty if using profiles/roles
}
variable "project_name" {
  description = "Project name to prefix all resources for uniqueness"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use"
  type        = string
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs for RDS (minimum 2 required)"
  type        = list(string)
  validation {
    condition     = length(var.existing_subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for RDS subnet group."
  }
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL master password (leave empty to auto-generate)"
  type        = string
  sensitive   = true # Mark as sensitive so it's not shown in plan output
  default     = ""   # Default to empty to trigger random generation
  validation {
    condition     = var.db_password == "" || length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long if provided."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access PostgreSQL"
  type        = list(string)
  default     = [] # Default to VPC-only access
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage in GB"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting"
  type        = bool
  default     = false
}
# DynamoDB Variables
variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "dynamodb_stream_enabled" {
  description = "Enable DynamoDB streams"
  type        = bool
  default     = true
}




variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_environment_id" {
  description = "Confluent Cloud Environment ID to reuse"
  type        = string
}

# --- Kafka Cluster Variables ---
variable "kafka_cluster_display_name" {
  description = "Display name for the Kafka Cluster"
  type        = string
}

variable "kafka_cluster_cloud" {
  description = "Cloud provider for the Kafka Cluster (e.g., AWS, GCP, AZURE)"
  type        = string
}

variable "kafka_cluster_region" {
  description = "Region for the Kafka Cluster (e.g., us-east-1)"
  type        = string
}




variable "postgres_db_port" {
  description = "Port of the PostgreSQL database"
  type        = string
}


variable "postgres_table_include_list" {
  description = "Comma-separated list of tables to include for CDC (e.g., 'public.products,public.orders')"
  type        = string
}
variable "postgres_db_name" {
  description = "Database name in PostgreSQL"
  type        = string
}

variable "postgres_connector_tasks_max" {
  description = "Maximum number of tasks for the PostgreSQL CDC connector"
  type        = number
}

variable "postgres_db_sslmode" {
  description = "SSL mode for PostgreSQL connection (e.g., require, prefer)"
  type        = string
}

variable "postgres_after_state_only" {
  description = "Whether to capture only after-state for PostgreSQL CDC"
  type        = string
}

# DynamoDB CDC Source Connector Variables
variable "dynamodb_topic_prefix" {
  description = "Topic prefix for DynamoDB CDC topics"
  type        = string
  default     = "dynamodb-cdc"
}

variable "dynamodb_table_discovery_mode" {
  description = "DynamoDB table discovery mode (INCLUDELIST, TAG, or ALL)"
  type        = string
  default     = "INCLUDELIST"
}

variable "dynamodb_table_sync_mode" {
  description = "DynamoDB table sync mode (SNAPSHOT, CDC, or SNAPSHOT_CDC)"
  type        = string
  default     = "SNAPSHOT_CDC"
}

variable "dynamodb_max_batch_size" {
  description = "Maximum batch size for DynamoDB connector"
  type        = string
  default     = "1000"
}

variable "dynamodb_poll_linger_ms" {
  description = "Poll linger time in milliseconds"
  type        = string
  default     = "5000"
}

variable "dynamodb_snapshot_max_poll_records" {
  description = "Maximum poll records for snapshot"
  type        = string
  default     = "1000"
}

variable "dynamodb_cdc_max_poll_records" {
  description = "Maximum poll records for CDC"
  type        = string
  default     = "5000"
}

variable "dynamodb_connector_tasks_max" {
  description = "Maximum number of tasks for DynamoDB connector"
  type        = string
  default     = "1"
}
# --- Flink Variables ---
variable "flink_compute_pool_max_cfu" {
  description = "Maximum CFU for the Flink Compute Pool"
  type        = number
}