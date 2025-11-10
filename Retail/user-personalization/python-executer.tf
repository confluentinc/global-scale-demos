resource "null_resource" "run_postgres_prerequisites_script" {
  # This triggers the script every time the RDS instance is created or changed.
  # This makes the null_resource dependent on the RDS instance.
  triggers = {
    db_id = aws_db_instance.postgresql.id
  }

  provisioner "local-exec" {
    command = "python3 postgres.py ${aws_db_instance.postgresql.address} ${aws_db_instance.postgresql.port} ${aws_db_instance.postgresql.db_name} ${aws_db_instance.postgresql.username} ${var.db_password}"
    }
}

resource "null_resource" "run_dynamodb_prerequisites_script" {
  # This triggers the script every time the RDS instance is created or changed.
  # This makes the null_resource dependent on the RDS instance.
  triggers = {
    dynamodb_table_id = aws_dynamodb_table.user_personalization.id
  }

  provisioner "local-exec" {
    command = "python3 dynamodb.py ${var.access_key} ${var.secret_key} ${var.aws_region} ${var.project_name}"
    }
}