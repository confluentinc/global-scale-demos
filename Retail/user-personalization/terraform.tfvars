
#AWS variables 
aws_region          = "us-east-1"
existing_vpc_id     = "vpc-1cf57167"  # Replace with your actual VPC ID
existing_subnet_ids = ["subnet-02c53b48","subnet-83288c8c"]  # Replace with your actual subnet IDs
db_username         = "postgres"
db_password         = "YourSecurePassword123!"
environment         = "dev"


# Confluent cloud variables

confluent_environment_id   = "env-rzk07k"                         # Your Confluent Cloud Environment ID

# --- Kafka Cluster Variables ---
kafka_cluster_display_name = "user-personalization"          # Display name for your Kafka Cluster
kafka_cluster_cloud        = "AWS"                                # Cloud provider (e.g., "AWS", "GCP", "AZURE")
kafka_cluster_region       = "us-east-1"                          # Region for your Kafka Cluster

# --- PostgreSQL CDC Connector Variables ---
postgres_db_port           = "5432"                               # Port of your PostgreSQL database
postgres_db_name           = "UserDB"                         # Database name in PostgreSQL
postgres_connector_tasks_max = 1                                  # Max tasks for the PostgreSQL CDC connector
postgres_db_sslmode        = "require"                            # SSL mode for PostgreSQL connection
postgres_after_state_only  = "true"                               # Whether to capture only after-state for PostgreSQL CDC
postgres_table_include_list = "user_data.categories,user_data.items,user_data.users,user_data.reviews"

# --- Flink Variables ---
flink_compute_pool_max_cfu = 20                                   # Maximum CFU for the Flink Compute Pool
