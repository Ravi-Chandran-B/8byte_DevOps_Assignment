resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/rds/credentials"
  description = "Master credentials for ${var.project_name} RDS instance"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    dbname   = var.db_name
    engine   = "postgres"
    port     = 5432
    host     = aws_db_instance.main.address
  })
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  multi_az                = var.db_multi_az
  publicly_accessible     = false

  backup_retention_period = 1
  backup_window            = "03:00-04:00"
  maintenance_window        = "mon:04:30-mon:05:30"
  copy_tags_to_snapshot   = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  deletion_protection = false

  tags = {
    Name = "${var.project_name}-db"
  }
}
