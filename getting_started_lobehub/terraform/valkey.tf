/*
============================================================================
Minimal Valkey/Redis configuration
============================================================================
Deploys Amazon ElastiCache for Valkey for LobeHub's cache and session state.
*/

/*
----------------------------------------------------------------------------
Connection Details
----------------------------------------------------------------------------
*/

locals {
  valkey_port    = aws_elasticache_replication_group.valkey.port
  valkey_address = "${aws_elasticache_replication_group.valkey.primary_endpoint_address}:${local.valkey_port}"
}

/*
----------------------------------------------------------------------------
ElastiCache Replication Group
----------------------------------------------------------------------------
*/

resource "aws_elasticache_subnet_group" "valkey" {
  name        = "${local.name_prefix}-valkey"
  subnet_ids  = module.vpc.subnets_ids
  description = "${local.name_prefix}-valkey"
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id       = "${local.name_prefix}-valkey"
  description                = "${local.name_prefix}-valkey"
  engine                     = "valkey"
  node_type                  = "cache.t4g.micro"
  port                       = 6379
  num_node_groups            = 1
  replicas_per_node_group    = 0
  cluster_mode               = "disabled"
  subnet_group_name          = aws_elasticache_subnet_group.valkey.name
  security_group_ids         = [aws_security_group.valkey.id]
  at_rest_encryption_enabled = true
  kms_key_id                 = module.vpc.kms_key_arn
  transit_encryption_enabled = true
  auth_token                 = random_password.valkey_auth_token.result
  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "random_password" "valkey_auth_token" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
Network Configuration
----------------------------------------------------------------------------
*/

resource "aws_security_group" "valkey" {
  name   = "${local.name_prefix}-valkey"
  vpc_id = module.vpc.vpc_id
}
