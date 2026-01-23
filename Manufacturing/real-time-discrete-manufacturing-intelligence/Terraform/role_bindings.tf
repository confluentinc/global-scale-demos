
resource "confluent_role_binding" "flink_assigner" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.flink_sa.id}"
}
resource "confluent_role_binding" "flink_sa_cluster_admin" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}
resource "confluent_role_binding" "flink_sr_read" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${data.confluent_schema_registry_cluster.essentials.resource_name}/subject=*"
}

resource "confluent_role_binding" "flink_sr_write" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${data.confluent_schema_registry_cluster.essentials.resource_name}/subject=*"
}

resource "confluent_role_binding" "connect_sa_cluster_admin" {
  principal   = "User:${confluent_service_account.connect_sa.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}

# Allow flink_sa to submit statements to Flink in this environment
resource "confluent_role_binding" "flink_sa_developer" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
}

resource "confluent_role_binding" "flink_sa_flink_admin" {
  principal   = "User:${confluent_service_account.flink_sa.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.confluent_project_env.resource_name
}
