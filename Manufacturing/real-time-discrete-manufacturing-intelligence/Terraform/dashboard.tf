resource "docker_image" "shopfloor_dashboard" {
  name = "shopfloor-dashboard:${var.project_name}"
  build {
    context = "shopfloor_dashboard"
    dockerfile = "Dockerfile"
  }
  depends_on = [ 
  confluent_connector.postgres_sink_insert,
  confluent_connector.postgres_sink_upsert
  ] 
}

resource "docker_container" "dashboard_container" {
  name  = "${var.project_name}-shopfloor-dashboard"
  image = docker_image.shopfloor_dashboard.name
  
  env = [
    "DB_HOST=${aws_db_instance.postgres_db.address}",
    "DB_USER=${var.postgres_user}",
    "DB_PASSWORD=${var.postgres_password}",
    "DB_NAME=${var.postgres_db_name}"
  ]
  ports {
    internal = 8050   # container port
    external = 8050   # host port
  }
  start      = true
  restart    = "on-failure"
  must_run   = true
  depends_on = [confluent_connector.postgres_sink_insert,confluent_connector.postgres_sink_upsert]
}
