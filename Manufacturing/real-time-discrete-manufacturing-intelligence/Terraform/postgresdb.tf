module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  # Basic VPC Configuration
  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  # Subnet and AZ Configuration
  azs = ["${var.cloud_region}a", "${var.cloud_region}b", "${var.cloud_region}c"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # Gateway Configuration
  enable_nat_gateway = false
  single_nat_gateway = false

  # Tagging for all resources created by the module
  tags = {
    "Project"   = "${var.project_name}"
    "ManagedBy" = "Terraform"
  }
}

resource "aws_security_group" "instance" {
  name = "${var.project_name}-aws-sg"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = "${var.postgres_port}"
    to_port     = "${var.postgres_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "postgres_db_subnet_group" {
  name       = "${var.project_name}-postgres-db-subnet-group"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_parameter_group" "postgres_debezium_parameter_group" {
  name   = replace("${var.project_name}-postgres-parameter-group", "_", "-")
  family = "postgres18"

  parameter {
    name  = "rds.logical_replication"
    value = 1
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "postgres_db" {
  identifier                          = replace("${var.project_name}-postgres","_","-")
  allocated_storage                   = 50
  engine                              = "postgres"
  engine_version                      = "18.1"
  instance_class                      = "db.t3.micro"
  port                                = "${var.postgres_port}"
  username                            = "${var.postgres_user}"
  password                            = "${var.postgres_password}"

  parameter_group_name                = aws_db_parameter_group.postgres_debezium_parameter_group.name
  skip_final_snapshot                 = true
  deletion_protection                 = false
  publicly_accessible                 = true
  vpc_security_group_ids              = [aws_security_group.instance.id]
  storage_encrypted                   = true
  backup_retention_period             = 3
  iam_database_authentication_enabled = true
  db_subnet_group_name   = aws_db_subnet_group.postgres_db_subnet_group.name
  depends_on = [
    aws_db_parameter_group.postgres_debezium_parameter_group
  ]
}
