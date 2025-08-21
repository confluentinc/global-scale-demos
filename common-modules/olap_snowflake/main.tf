terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.17.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.31.0"
    }
    snowflake = {
      source = "snowflakedb/snowflake"
      version = "2.1.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  snowflake_s3_access_role_name = "${var.project_name}-snowflake-access-role"
  snowflake_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.snowflake_s3_access_role_name}"  
}

resource "snowflake_warehouse" "warehouse" {
  name                                = "${var.project_name}-warehouse"
  warehouse_size                      = "X-SMALL"
}

resource "snowflake_database" "primary" {
  name = "${var.project_name}-database"
  depends_on = [
    snowflake_warehouse.warehouse
  ]
}

resource "snowflake_external_volume" "external_volume" {
  name  = "${var.project_name}-external-volume"
  storage_location  { 
    storage_provider = "S3"
    storage_aws_role_arn = local.snowflake_s3_access_role_arn
    storage_base_url = "s3://${var.tableflow_s3_bucket}/"
    storage_location_name = "${var.project_name}-${var.aws_region}-s3"
  }

  allow_writes = true
}


resource "aws_iam_role" "snowflake_s3_access_role" {
  name = "${var.project_name}-snowflake-access-role"
  description = "IAM role for accessing S3 with a trust policy for Snowflake"
  
      assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = jsondecode(snowflake_external_volume.external_volume.describe_output[1].value).STORAGE_AWS_IAM_USER_ARN
        }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = jsondecode(snowflake_external_volume.external_volume.describe_output[1].value).STORAGE_AWS_EXTERNAL_ID
          }
        }
      }
    ]
  })
  depends_on = [
    snowflake_external_volume.external_volume,
  ]
}


resource "aws_iam_policy" "snowflake_s3_access_policy" {
  name        = "${var.project_name}-snowflake-access-policy"
  description = "IAM policy for accessing the S3 bucket for Snowflake"

  policy = jsonencode({
   "Version": "2012-10-17",
   "Statement": [
         {
            "Effect": "Allow",
            "Action": [
               "s3:PutObject",
               "s3:GetObject",
               "s3:GetObjectVersion",
               "s3:DeleteObject",
               "s3:DeleteObjectVersion"
            ],
            "Resource": "${var.tableflow_s3_bucket_arn}/*"
         },
         {
            "Effect": "Allow",
            "Action": [
               "s3:ListBucket",
               "s3:GetBucketLocation"
            ],
            "Resource": "${var.tableflow_s3_bucket_arn}",
            "Condition": {
               "StringLike": {
                     "s3:prefix": [
                        "*"
                     ]
               }
            }
         }
   ]
})
  depends_on = [
    snowflake_external_volume.external_volume,
  ]
}

resource "aws_iam_role_policy_attachment" "snowflake_role_policy_attachment" {
  role       = aws_iam_role.snowflake_s3_access_role.name
  policy_arn = aws_iam_policy.snowflake_s3_access_policy.arn
  depends_on = [
    aws_iam_policy.snowflake_s3_access_policy,
    aws_iam_role.snowflake_s3_access_role

  ]
}






resource "null_resource" "create_snowflake_external_catalog" {
  provisioner "local-exec" {
    command = <<EOT
        docker exec ${var.project_name}-tools bash -c "export SNOWSQL_PWD='${var.snowflake_password}' &&  snowsql -a ${var.snowflake_account_name} -r ${var.snowflake_role} -u ${var.snowflake_username} -w ${var.project_name}-warehouse -q \"CREATE OR REPLACE CATALOG INTEGRATION \\\"${var.project_name}-rest-catalog-integration\\\" \
        CATALOG_SOURCE=ICEBERG_REST \
        TABLE_FORMAT=ICEBERG \
        CATALOG_NAMESPACE='${var.kafka_id}' \
        REST_CONFIG = ( \
        CATALOG_URI = '${var.confluent_rest_catalog_uri}' \
        CATALOG_API_TYPE = PUBLIC \
        ) \
        REST_AUTHENTICATION=( \
        TYPE=OAUTH \
        OAUTH_CLIENT_ID='${var.tableflow_reader_api_key_id}' \
        OAUTH_CLIENT_SECRET='${var.tableflow_reader_api_key_secret}' \
        OAUTH_ALLOWED_SCOPES=('catalog') \
        ) \
        ENABLED=true;\" "
    EOT
  }
}


resource "null_resource" "create_snowflake_iceberg_table" {
  provisioner "local-exec" {
    command = <<EOT
        sleep 120
        docker exec ${var.project_name}-tools bash -c "export SNOWSQL_PWD='${var.snowflake_password}' && export SNOWSQL_DATABASE='\"${snowflake_database.primary.name}\"' && export SNOWSQL_WAREHOUSE='\"${snowflake_warehouse.warehouse.name}\"' &&  snowsql -a ${var.snowflake_account_name} -r ${var.snowflake_role} -u ${var.snowflake_username} -s public -q \"CREATE OR REPLACE ICEBERG TABLE low_stock_alerts EXTERNAL_VOLUME = '\\\"${snowflake_external_volume.external_volume.name}\\\"' CATALOG = '\\\"${var.project_name}-rest-catalog-integration\\\"' CATALOG_TABLE_NAME = 'low_stock_alerts';\" "
    EOT
  }
  depends_on = [
    snowflake_database.primary ,
    snowflake_external_volume.external_volume,
    null_resource.create_snowflake_external_catalog

  ]
}