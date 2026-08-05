/*
============================================================================
stdapi.ai with Docling Deployment
============================================================================
This configuration deploys stdapi.ai as a backend service (no ALB) with
Docling Serve as a public HTTP API, exposed via an ALB. Docling has no web
UI: it is a document-conversion API you call directly (see the README for
a working `curl` example).

Features:
- stdapi.ai as internal OpenAI-compatible API backend
- Docling Serve with a public ALB
- Docling's VLM pipeline routed to Amazon Bedrock through stdapi.ai
- IP address restriction (your current IP only)
- API key authentication
============================================================================
*/

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
  Models will be accessed from these regions in order of preference

  Select between EU and US configuration.
  */
  aws_bedrock_regions = distinct([
    data.aws_region.current.region, # Current region (primary)
    # Common US regions to access almost all models
    "us-east-1", # N. Virginia
    "us-west-2", # Oregon
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
