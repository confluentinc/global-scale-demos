resource "docker_image" "tools_image" {
  name = "demotools:${var.project_name}"

  build {
    context    = "tools"
    dockerfile = "Dockerfile"
  }

  depends_on = [
    aws_db_parameter_group.postgres_debezium_parameter_group
  ]
}

resource "docker_container" "tools_container" {
  name     = "${var.project_name}-tools"
  image    = docker_image.tools_image.name
  start    = true
  must_run = true
  
  depends_on = [
    aws_db_instance.postgres_db,
    docker_image.tools_image
  ]

    command = [
   "sleep",
   "infinity"
  ]
}


# Execute the SQL file
resource "null_resource" "run_postgres_initial" {
  provisioner "local-exec" {
    command = <<-EOT
      docker cp postgres-initial.sql ${var.project_name}-tools:/tmp/postgres-initial.sql
      docker exec ${var.project_name}-tools bash -c "PGPASSWORD='${var.postgres_password}' psql -h ${aws_db_instance.postgres_db.address} -p 5432 -U ${var.postgres_user} -d ${var.postgres_db_name} -f /tmp/postgres-initial.sql"
    EOT
  }
  depends_on = [
    aws_db_instance.postgres_db,
    docker_container.tools_container

  ]
}