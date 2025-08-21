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
    
    databricks = {
      source  = "databricks/databricks"
      version = ">=1.83.0"
    }
}
}

data "aws_caller_identity" "current" {}

locals {
  databricks_s3_access_role_name = "${var.project_name}-databricks-access-role"
  databricks_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.databricks_s3_access_role_name}"  
}

resource "databricks_storage_credential" "external" {
  name = local.databricks_s3_access_role_name
  aws_iam_role {
    role_arn = local.databricks_s3_access_role_arn
  }
}

resource "aws_iam_role" "databricks_s3_access_role" {
  name = local.databricks_s3_access_role_name
  description = "IAM role for accessing S3 with a trust policy for Databricks"
  
      assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = databricks_storage_credential.external.aws_iam_role[0].unity_catalog_iam_arn
        }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = databricks_storage_credential.external.aws_iam_role[0].external_id
          }
        }
      }
                  
    ]
  })
  depends_on = [
    databricks_storage_credential.external
  ]
}


resource "aws_iam_policy" "databricks_s3_access_policy" {
  name        = "${var.project_name}-databricks-access-policy"
  description = "IAM policy for accessing the S3 bucket for Databricks"

  policy = jsonencode({
	"Version": "2012-10-17",
	"Statement": [
		{
			"Action": [
				"s3:GetObject",
				"s3:PutObject",
				"s3:DeleteObject",
				"s3:ListBucket",
				"s3:GetBucketLocation",
				"s3:ListBucketMultipartUploads",
				"s3:ListMultipartUploadParts",
				"s3:AbortMultipartUpload"
			],
			"Resource": [
				"arn:aws:s3:::${var.tableflow_s3_bucket}/*",
				"arn:aws:s3:::${var.tableflow_s3_bucket}"
			],
			"Effect": "Allow"
		}
	]
})
  depends_on = [
    databricks_storage_credential.external
  ]
}

resource "aws_iam_role_policy_attachment" "databricks_role_policy_attachment" {
  role       = aws_iam_role.databricks_s3_access_role.name
  policy_arn = aws_iam_policy.databricks_s3_access_policy.arn
  depends_on = [
    aws_iam_policy.databricks_s3_access_policy,
    aws_iam_role.databricks_s3_access_role
  ]
}



resource "databricks_grants" "external_cred_ui_access" {
  storage_credential = databricks_storage_credential.external.id
  grant {
    principal  = var.databricks_ui_user
    privileges = ["CREATE_EXTERNAL_TABLE","READ_FILES","MANAGE"]
  }
  depends_on = [ aws_iam_role_policy_attachment.databricks_role_policy_attachment ]
}

resource "databricks_grants" "external_location_ui_access" {
  external_location = databricks_external_location.tableflow_s3.id
  grant {
    principal  = var.databricks_ui_user
    privileges = ["CREATE_EXTERNAL_TABLE", "READ_FILES","MANAGE"]
  }
  depends_on = [ aws_iam_role_policy_attachment.databricks_role_policy_attachment ]
}

resource "null_resource" "wait" {
  
  provisioner "local-exec" {
    command = <<EOT
        sleep 30
    EOT
  }

  depends_on = [aws_iam_role_policy_attachment.databricks_role_policy_attachment]
}

resource "databricks_external_location" "tableflow_s3" {
  name            = "${var.project_name}-tableflow-s3-location"
  url             = "s3://${var.tableflow_s3_bucket}"
  credential_name = databricks_storage_credential.external.id
  depends_on = [ databricks_grants.external_cred_ui_access , null_resource.wait ]
  skip_validation = true
}

resource "databricks_catalog" "catalog" {
  name    = "${var.project_name}-catalog"
  storage_root = "s3://${var.tableflow_s3_bucket}/"
  depends_on = [ databricks_external_location.tableflow_s3  ]
}

resource "databricks_schema" "schema" {
  catalog_name = databricks_catalog.catalog.id
  name         = "demoschema"
  properties = {
    kind = "various"
  }
  force_destroy = true
}

resource "databricks_grant" "schema_ui_access" {
  schema = databricks_schema.schema.id

  principal  = var.databricks_ui_user
  privileges = ["USE_SCHEMA", "MODIFY","MANAGE"]
}

resource "databricks_grant" "catalog_ui_access" {
  catalog = databricks_catalog.catalog.name

  principal  = var.databricks_ui_user
  privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "MODIFY","MANAGE"]

  depends_on = [ databricks_catalog.catalog ]
}

# resource "databricks_sql_table" "stocks" {
#   name               = "low_stock_alerts"
#   catalog_name       = databricks_catalog.catalog
#   schema_name        = databricks_schema.schema
#   table_type         = "EXTERNAL"
#   storage_location   = ""

# }

