provider "aws" {
  region = var.aws_region
  
  access_key = var.access_key  
  secret_key = var.secret_key  
}

data "aws_vpc" "existing" {
  id = var.existing_vpc_id
}

# Random password for RDS (if not provided by db_password variable)
resource "random_password" "db_password_generated" {
  count   = var.db_password == "" ? 1 : 0
  length  = 16
  special = true
}

# KMS key for RDS encryption
resource "aws_kms_key" "postgres_key" {
  description             = "KMS key for ${var.project_name}-${var.environment} PostgreSQL RDS encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-kms-key"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_kms_alias" "postgres_key_alias" {
  name          = "alias/${var.project_name}-${var.environment}-postgres-key"
  target_key_id = aws_kms_key.postgres_key.key_id
}

# Store the RDS password in SSM Parameter Store
resource "aws_ssm_parameter" "rds_password_param" {
  name        = "/${var.project_name}/${var.environment}/rds/postgres/password"
  description = "PostgreSQL master password for ${var.project_name}-${var.environment} RDS instance"
  type        = "SecureString"
  value       = var.db_password != "" ? var.db_password : random_password.db_password_generated[0].result
  key_id      = aws_kms_key.postgres_key.key_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-rds-password"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DB Subnet Group using existing subnets
resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "${var.project_name}-${var.environment}-postgres-subnet-group"
  subnet_ids = var.existing_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Security Group for PostgreSQL RDS
resource "aws_security_group" "postgres_sg" {
  name_prefix = "${var.project_name}-${var.environment}-postgres-sg"
  vpc_id      = var.existing_vpc_id

  # PostgreSQL port access from within VPC
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "PostgreSQL access from VPC"
  }
  
  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL access from Internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-security-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "postgres_monitoring" {
  name = "${var.project_name}-${var.environment}-postgres-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-monitoring-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "postgres_monitoring" {
  role       = aws_iam_role.postgres_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# DB Parameter Group for PostgreSQL optimization
resource "aws_db_parameter_group" "postgres_params_terr" {
  family = "postgres17"
  name   = "${var.project_name}-${var.environment}-postgres-db-terraform"

  parameter {
    name         = "rds.logical_replication"
    value        = "1" 
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-params-terr"
    Environment = var.environment
    Project     = var.project_name
  }
}

# PostgreSQL RDS Instance
resource "aws_db_instance" "postgresql" {
  identifier = "${var.project_name}-${var.environment}-postgres-db-terraform"
  
  # Engine configuration
  engine               = "postgres"
  engine_version       = "17.5"
  instance_class       = var.instance_class
  parameter_group_name = aws_db_parameter_group.postgres_params_terr.name

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.postgres_key.arn
  
  # Database configuration
  db_name  = var.postgres_db_name
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db_password_generated[0].result
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.postgres_subnet_group.name
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]
  publicly_accessible    = true 
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"
  copy_tags_to_snapshot   = true
  
  # Monitoring
  monitoring_interval           = 60
  monitoring_role_arn           = aws_iam_role.postgres_monitoring.arn
  performance_insights_enabled  = true
  performance_insights_retention_period = 7
  
  # Security settings
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-postgres-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  deletion_protection       = var.deletion_protection
  
  # Enable automatic minor version updates
  auto_minor_version_upgrade = true
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-db"
    Environment = var.environment
    Project     = var.project_name
  }
}

##############################################################################################################################################################
# DynamoDB Table
##############################################################################################################################################################

# DynamoDB table for user personalization data
resource "aws_dynamodb_table" "user_personalization" {
  name           = "${var.project_name}-${var.environment}-user-personalization"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"
  range_key      = "timestamp"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"  
  }

  # Global Secondary Index for querying by other attributes
  global_secondary_index {
    name            = "${var.project_name}-user-activity-index"
    hash_key        = "user_id"
    range_key       = "activity_type"
    projection_type = "ALL"
  }

  attribute {
    name = "activity_type"
    type = "S"
  }

  # TTL configuration
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  # Stream configuration for change data capture
  stream_enabled   = var.dynamodb_stream_enabled
  stream_view_type = "NEW_IMAGE" 

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-personalization-table"
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "UserPersonalization"
  }
}

# KMS key for DynamoDB encryption
resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS key for ${var.project_name}-${var.environment} DynamoDB encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-dynamodb-kms-key"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_kms_alias" "dynamodb_key_alias" {
  name          = "alias/${var.project_name}-${var.environment}-dynamodb-key"
  target_key_id = aws_kms_key.dynamodb_key.key_id
}

# CloudWatch Log Group for DynamoDB
resource "aws_cloudwatch_log_group" "dynamodb_logs" {
  name              = "/aws/dynamodb/${var.project_name}-${var.environment}-${aws_dynamodb_table.user_personalization.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-dynamodb-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}
