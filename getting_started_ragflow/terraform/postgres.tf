/*
============================================================================
Minimal Aurora PostgreSQL configuration
============================================================================
Deploys Amazon Aurora PostgreSQL as RAGFlow's metadata database.
*/

/*
----------------------------------------------------------------------------
Connection Details
----------------------------------------------------------------------------
*/

locals {
  postgres_address = aws_rds_cluster.postgres.endpoint
  postgres_port    = aws_rds_cluster.postgres.port

  postgres_ragflow_username = "ragflow"
  postgres_ragflow_password = random_password.postgres_ragflow_user.result
  postgres_ragflow_database = "ragflow"

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
  database_name      = local.postgres_ragflow_database

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

resource "random_password" "postgres_ragflow_user" {
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
User Initialization
----------------------------------------------------------------------------
RAGFlow creates its own schema on start ("ensure_db_init" in the image
entry point), so only an empty database and a login role need to pre-exist.
*/

resource "null_resource" "postgres_app_user" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_ragflow_username
    password    = local.postgres_ragflow_password
  }
  provisioner "local-exec" {
    # Password is passed via environment variable to keep it out of the command line
    command = "${local.rds_data_exec} --database ${local.postgres_ragflow_database} --sql \"DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '${local.postgres_ragflow_username}') THEN CREATE ROLE ${local.postgres_ragflow_username} WITH LOGIN PASSWORD '$POSTGRES_APP_PASSWORD'; END IF; END \\$\\$;\""
    environment = {
      POSTGRES_APP_PASSWORD = local.postgres_ragflow_password
    }
  }
  depends_on = [aws_rds_cluster_instance.postgres, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_database_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_ragflow_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_ragflow_database} --sql \"GRANT ALL PRIVILEGES ON DATABASE ${local.postgres_ragflow_database} TO ${local.postgres_ragflow_username};\""
  }
  depends_on = [null_resource.postgres_app_user, aws_secretsmanager_secret_version.postgres_master]
}

resource "null_resource" "grant_schema_privileges" {
  triggers = {
    cluster_arn = aws_rds_cluster.postgres.arn
    username    = local.postgres_ragflow_username
  }
  provisioner "local-exec" {
    command = "${local.rds_data_exec} --database ${local.postgres_ragflow_database} --sql \"GRANT ALL ON SCHEMA public TO ${local.postgres_ragflow_username};\""
  }
  depends_on = [null_resource.grant_database_privileges, aws_secretsmanager_secret_version.postgres_master]
}
