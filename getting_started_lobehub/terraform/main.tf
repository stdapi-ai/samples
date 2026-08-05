/*
============================================================================
stdapi.ai with LobeHub Deployment
============================================================================
This configuration deploys stdapi.ai as a backend service (no ALB) with
LobeHub as the frontend accessible via ALB.

LobeHub 2.x dropped its client-storage (PGlite) mode; the current app only
supports "server DB" mode, which requires a Postgres extension (ParadeDB's
pg_search, used for full-text search in the knowledge base) that Amazon RDS
for PostgreSQL does not support. This sample therefore self-hosts Postgres
(the official ParadeDB image, which bundles pg_search and pgvector) as an
ECS task backed by EFS instead of using RDS. See postgres.tf and the README
for details.

Features:
- stdapi.ai as internal OpenAI-compatible API backend
- LobeHub with public ALB, server DB mode (self-hosted ParadeDB Postgres)
- ElastiCache Valkey for cache/session state
- Amazon S3 for file/avatar/knowledge-base storage
- IP address restriction (your current IP only)
- API key authentication
============================================================================
*/

/*
----------------------------------------------------------------------------
Container Image Tags
----------------------------------------------------------------------------
Centralized image tag definitions for all container images
*/

locals {
  lobehub_image_tag  = "2.2.13"
  postgres_image_tag = "0.25.1-pg17" # ParadeDB, bundles pg_search + pgvector on Postgres 17
}

/*
----------------------------------------------------------------------------
Main stdapi.ai Module
----------------------------------------------------------------------------
Deploys the stdapi.ai service with all required infrastructure
*/

module "stdapi_ai" {
  source  = "stdapi-ai/stdapi-ai/aws"
  version = "~> 1.0"

  /*
  --------------------------------------------------------------------------
  Use existing network configuration
  --------------------------------------------------------------------------
  */
  subnet_ids        = module.vpc.subnets_ids
  security_group_id = module.vpc.security_group_id

  /*
  --------------------------------------------------------------------------
  Service Discovery Configuration
  --------------------------------------------------------------------------
  */
  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "stdapi-ai"

  /*
  --------------------------------------------------------------------------
  Amazon Bedrock Multi-Region Configuration
  --------------------------------------------------------------------------
  Models will be accessed from these regions in order of preference.
  us-west-2 is required for the Stability image-generation models used below.

  Select between EU and US configuration.
  */
  aws_bedrock_regions = distinct([
    data.aws_region.current.region, # Current region (primary)
    # Common US regions to access almost all models
    "us-east-1", # N. Virginia
    "us-west-2", # Oregon (Stability image-generation models)
    "us-east-2", # Ohio

    # EU regions
    # "eu-west-3",    # Paris (primary)
    # "eu-west-1",    # Ireland
    # "eu-central-1", # Frankfurt
    # "eu-north-1",    # Stockholm
  ])

  /*
  --------------------------------------------------------------------------
  Sovereignty/data residency configuration (e.g. GDPR)
  --------------------------------------------------------------------------
  Amazon Bedrock global cross-region inference:
  true (default) prefers availability by letting Bedrock route requests
  through its global inference profiles; set to false for data sovereignty,
  keeping all traffic within your selected aws_bedrock_regions (EU or US)
  */
  aws_bedrock_cross_region_inference_global = true

  /*
  --------------------------------------------------------------------------
  Security Configuration
  --------------------------------------------------------------------------
  Generate API key for authentication
  */
  api_key_create = true
}

/*
----------------------------------------------------------------------------
Service Discovery
----------------------------------------------------------------------------
Private DNS namespace for internal service communication
*/

locals {
  internal_namespace = local.name_prefix

  /*
  The ID stays unknown until the namespace is created, but coalesce() marks it
  as never null. Modules that decide whether to create service discovery
  entries by comparing it to null can then resolve that decision during the
  first plan, which keeps a single `terraform apply` working on an empty state.
  */
  internal_namespace_id = coalesce(aws_service_discovery_private_dns_namespace.internal.id)
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = local.internal_namespace
  vpc  = module.vpc.vpc_id
}

/*
----------------------------------------------------------------------------
Data Sources
----------------------------------------------------------------------------
Automatically detect your current public IP address for ALB security group
*/

locals {
  stdapi_url            = "http://${module.stdapi_ai.service_discovery_service_name}.${local.internal_namespace}:${module.stdapi_ai.port}"
  stdapi_openai_api_url = "${local.stdapi_url}/v1"
  name_prefix           = module.stdapi_ai.name_prefix
}

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
