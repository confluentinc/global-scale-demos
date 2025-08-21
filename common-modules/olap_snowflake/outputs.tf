output "snowflake_external_volume_name" {
   value = snowflake_external_volume.external_volume.name
}

output "snowflake_warehouse_name" {
   value = snowflake_warehouse.warehouse.name
}

output "snowflake_database_name" {
   value = snowflake_database.primary.name
}