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
  }
}


data "aws_caller_identity" "current" {}

locals {
  glue_access_role_name = "${var.project_name}-glue-access-role"
  glue_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.glue_access_role_name}"  
}




resource "confluent_provider_integration" "main" {
  display_name = "${var.project_name}_tableflow_glue_integration"
  environment {
    id = var.env_id
  }
  aws {
    # During the creation of confluent_provider_integration.main, the S3 role does not yet exist.
    # The role will be created after confluent_provider_integration.main is provisioned
    # by the s3_access_role module using the specified target name.
    # Note: This is a workaround to avoid updating an existing role or creating a circular dependency.
    customer_role_arn = local.glue_access_role_arn
  }
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal   = "User:${var.app_manager_user_id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${var.env_resource_name}/provider-integration=${confluent_provider_integration.main.id}"

}

resource "confluent_catalog_integration" "glue_tableflow_catalog_integeration" {
  environment {
    id = var.env_id
  }
  kafka_cluster {
    id = var.kafka_id
  }
  display_name = "glue_tableflow_catalog_integeration"
  aws_glue {
    provider_integration_id = confluent_provider_integration.main.id
  }
  credentials {
    key    = var.tableflow_admin_api_key_id
    secret = var.tableflow_admin_api_key_secret
  }

  depends_on = [ confluent_role_binding.app-manager-provider-integration-resource-owner ]
}


resource "aws_iam_role" "glue_tableflow_access_role" {
  name = "${local.glue_access_role_name}"
  description = "IAM role for accessing glue with a trust policy for Tableflow"
  
      assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = confluent_provider_integration.main.aws[0].iam_role_arn
        }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = confluent_provider_integration.main.aws[0].external_id
          }
        }
      },
        {
        Effect    = "Allow"
        Principal = {
          AWS = confluent_provider_integration.main.aws[0].iam_role_arn
        }
        Action    = "sts:TagSession"
        }
    ]
  })
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration
  ]
}


resource "aws_iam_policy" "glue_tableflow_access_policy" {
  name        = "${var.project_name}-glue-access-policy"
  description = "IAM policy for accessing glue for Tableflow"

  policy = jsonencode(
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "glue:GetTable",
                "glue:GetDatabase",
                "glue:DeleteTable",
                "glue:DeleteDatabase",
                "glue:CreateTable",
                "glue:CreateDatabase",
                "glue:UpdateTable",
                "glue:UpdateDatabase"
            ],
            "Resource": [
                "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
            ]
        }
    ]
}
    )
  depends_on = [
    confluent_catalog_integration.glue_tableflow_catalog_integeration
  ]
}

resource "aws_iam_role_policy_attachment" "glue_role_policy_attachment" {
  role       = aws_iam_role.glue_tableflow_access_role.name
  policy_arn = aws_iam_policy.glue_tableflow_access_policy.arn
  depends_on = [
    aws_iam_policy.glue_tableflow_access_policy,
    aws_iam_role.glue_tableflow_access_role
  ]
}
