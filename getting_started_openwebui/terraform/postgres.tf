/*
============================================================================
Minimal Aurora PostgreSQL configuration
============================================================================
Deploys Amazon Aurora PostgreSQL with the pgvector extension for embeddings.
*/

/*
----------------------------------------------------------------------------
Connection Details
----------------------------------------------------------------------------
*/

locals {
  postgres_address = aws_rds_cluster.postgres.endpoint
  postgres_port    = aws_rds_cluster.postgres.port

  postgres_openwebui_username        = "openwebui"
  postgres_openwebui_password        = random_password.postgres_openwebui_user.result
  postgres_openwebui_database        = "openwebui"
  postgres_openwebui_database_vector = "openwebui_vector"

  postgres_url_main   = "postgresql://${local.postgres_openwebui_username}:${random_password.postgres_openwebui_user.result}@${local.postgres_address}:${local.postgres_port}/${local.postgres_openwebui_database}"
  postgres_url_vector = "postgresql://${local.postgres_openwebui_username}:${random_password.postgres_openwebui_user.result}@${local.postgres_address}:${local.postgres_port}/${local.postgres_openwebui_database_vector}"

  rds_data_exec = "aws rds-data execute-statement --resource-arn ${aws_rds_cluster.postgres.arn} --secret-arn ${aws_secretsmanager_secret.postgres_master.arn}"
}

/*
----------------------------------------------------------------------------
Aurora Cluster
----------------------------------------------------------------------------
*/

resource "aws_rds_cluster" "postgres" {
  cluster_identifier = "${local.name_prefix}-postgres"
  engine             = "aurora-postgresql"
  database_name      = "openwebui"

  master_username = "postgres"
  master_password = random_password.postgres_master.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  skip_final_snapshot  = true
  enable_http_endpoint = true # Required for DB initialization

  storage_encrypted = true
  kms_key_id        = module.vpc.kms_key_arn

  serverlessv2_scaling_configuration {
    min_capacity = 0
    max_capacity = 8.0
  }
  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster_instance" "postgres" {
  cluster_identifier = aws_rds_cluster.postgres.id
  identifier_prefix  = "${local.name_prefix}-postgres-"
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version

  performance_insights_enabled    = true
  performance_insights_kms_key_id = module.vpc.kms_key_arn
}

/*
----------------------------------------------------------------------------
Network Configuration
----------------------------------------------------------------------------
*/

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-postgres"
  subnet_ids = module.vpc.subnets_ids
}

resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-postgres"
  description = "${local.name_prefix}-postgres"
  vpc_id      = module.vpc.vpc_id
}

/*
----------------------------------------------------------------------------
Root and User Passwords
----------------------------------------------------------------------------
*/

resource "random_password" "postgres_master" {
  length  = 32
  special = false
}

resource "random_password" "postgres_openwebui_user" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
Secrets Manager for RDS Data API
----------------------------------------------------------------------------
*/

resource "aws_secretsmanager_secret" "postgres_master" {
  name       = "${local.name_prefix}-postgres-master"
  kms_key_id = module.vpc.kms_key_arn
}

resource "aws_secretsmanager_secret_version" "postgres_master" {
  secret_id = aws_secretsmanager_secret.postgres_master.id
  secret_string = jsonencode({
    username = "postgres"
    password = random_password.postgres_master.result
  })
}

/*
----------------------------------------------------------------------------
Schema, Extensions, and Users Initialization
----------------------------------------------------------------------------
*/

resource "null_resource" "postgres_create_vector_database" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database} --sql \"CREATE DATABASE ${local.postgres_openwebui_database_vector};\""
  }
  depends_on = [aws_rds_cluster_instance.postgres, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "postgres_pgvector_extension" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database_vector} --sql \"CREATE EXTENSION IF NOT EXISTS vector;\""
  }
  depends_on = [null_resource.postgres_create_vector_database, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "postgres_app_user" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_openwebui_username
    password    = local.postgres_openwebui_password
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database} --sql \"DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '${local.postgres_openwebui_username}') THEN CREATE ROLE ${local.postgres_openwebui_username} WITH LOGIN PASSWORD '${local.postgres_openwebui_password}'; END IF; END \\$\\$;\""
  }
  depends_on = [null_resource.postgres_pgvector_extension, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_database_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_openwebui_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database} --sql \"GRANT ALL PRIVILEGES ON DATABASE openwebui TO ${local.postgres_openwebui_username};\""
  }
  depends_on = [null_resource.postgres_app_user, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_schema_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_openwebui_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database} --sql \"GRANT ALL ON SCHEMA public TO ${local.postgres_openwebui_username};\""
  }
  depends_on = [null_resource.grant_database_privileges, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_vector_database_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_openwebui_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database} --sql \"GRANT ALL PRIVILEGES ON DATABASE ${local.postgres_openwebui_database_vector} TO ${local.postgres_openwebui_username};\""
  }
  depends_on = [null_resource.grant_schema_privileges, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_vector_schema_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_openwebui_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_openwebui_database_vector} --sql \"GRANT ALL ON SCHEMA public TO ${local.postgres_openwebui_username};\""
  }
  depends_on = [null_resource.grant_vector_database_privileges, aws_secretsmanager_secret_version.postgres_master]
}
