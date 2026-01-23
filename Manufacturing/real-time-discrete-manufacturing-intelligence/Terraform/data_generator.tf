resource "docker_image" "data_generator_image" {
  name = "generate:data-${var.project_name}"
  build {
    context = "data_generator"
    dockerfile = "Dockerfile"
  }
  depends_on = [ aws_db_parameter_group.postgres_debezium_parameter_group ] 
}

resource "docker_container" "data_generator_container" {
  name  = "${var.project_name}-data-generator"
  image = docker_image.data_generator_image.name
  
  env = [
    "DB_HOST=${aws_db_instance.postgres_db.address}",
    "DB_USER=${var.postgres_user}",
    "DB_PASSWORD=${var.postgres_password}",
    "DB_NAME=${var.postgres_db_name}"
  ]
  start      = true
  restart    = "on-failure"
  must_run   = true
  depends_on = [aws_db_instance.postgres_db,null_resource.run_postgres_initial]
}
