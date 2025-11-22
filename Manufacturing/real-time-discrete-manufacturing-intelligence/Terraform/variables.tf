# Confluent Cloud API keys (org-scoped)
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

# Target environment and naming
variable "environment_id" {
  description = "Existing Environment ID (e.g., env-xxxxx)"
  type        = string
}

variable "environment_name" {
  description = "Existing Environment name "
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "demo"
}

# Cluster settings
variable "kafka_cluster_name" {
  type        = string
  default     = "basic_kafka_cluster"
}
variable "kafka_availability" {
  type        = string
  default     = "SINGLE_ZONE"
}
variable "cloud_provider" {
  type        = string
  default     = "AWS"
}
variable "cloud_region" {
  type        = string
  default     = "us-east-1"
}
variable "prevent_destroy" {
  type        = bool
  default     = true
}

# Postgres database connection (used by CDC source and Sink)
variable "postgres_host"       { type = string }
variable "postgres_port" {
  type = number
  default = 5432
}
variable "postgres_user"       { type = string }
variable "postgres_password"   {
  type = string
  sensitive = true
}
variable "postgres_db_name"    { type = string }
variable "postgres_sslmode"    {
  type = string
  default = "prefer"
} # prefer | require | verify-ca | verify-full

# CDC Source V2 settings
variable "cdc_topic_prefix"          {
  type = string
  default = "postgres"
}
variable "cdc_output_value_format"   {
  type = string
  default = "AVRO"
}     # AVRO | JSON_SR | PROTOBUF | JSON
variable "cdc_output_key_format"     {
  type = string
  default = "AVRO"
}     # AVRO | JSON_SR | PROTOBUF | JSON | STRING
variable "cdc_table_include_list"    {
  type = string
  default = ""
}         # optional

# Sink (INSERT)
variable "sink_insert_topics"        {
  type = string
  default = "flink_sink_1,flink_sink_2"
}

variable "sink_insert_value_format"  {
  type = string
  default = "AVRO"
}

variable "sink_insert_key_format"    {
  type = string
  default = "AVRO"
}

# Sink (UPSERT)
variable "sink_upsert_topics"        {
  type = string
  default = "flink_sink_upsert_1"
}

variable "sink_upsert_value_format"  {
  type = string
  default = "AVRO"
}

variable "sink_upsert_key_format"    {
  type = string
  default = "AVRO"
}

variable "sink_upsert_pk_mode"       {
  type = string
  default = "record_value"
}

variable "sink_upsert_pk_fields"     {
  type = string
  default = "id"
}

# Sink common
variable "sink_auto_create" {
  type = bool
  default = true
}

variable "sink_auto_evolve" {
  type = bool
  default = true
}

# Flink compute pool + SQL
variable "flink_pool_name" {
  type = string
  default = "standard_compute_pool"
}

variable "flink_max_cfu"   {
  type = number
  default = 5
}
