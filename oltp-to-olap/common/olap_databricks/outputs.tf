output "databricks_s3_access_role_name" {
    value = local.databricks_s3_access_role_name
}

output "databricks_s3_access_role_arn" {
    value = local.databricks_s3_access_role_arn
}

output "unity_catalog_role_arn" {
    value = databricks_storage_credential.external.aws_iam_role[0].unity_catalog_iam_arn
}

output "unity_catalog_name" {
    value = databricks_catalog.catalog.name
}