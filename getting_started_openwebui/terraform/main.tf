/*
============================================================================
stdapi.ai with Open WebUI Deployment
============================================================================
This configuration deploys stdapi.ai as a backend service (no ALB) with
Open WebUI as the frontend accessible via ALB.

Features:
- stdapi.ai as internal OpenAI-compatible API backend
- Open WebUI with public ALB
- SearXNG for web search
- Playwright for web scraping
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
  openwebui_image_tag = "v0.11.0-slim"
  searxng_image_tag   = "2026.7.26-b060c780d"

  /*
  Must match the version pinned in the Open WebUI release above (Search "playwright==")
  https://github.com/open-webui/open-webui/blob/v0.11.0/backend/requirements.txt
  */
  playwright_version = "1.60.0"
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
  Sovereignty/Compliance configuration (GDPR, HIPAA, ...)
  --------------------------------------------------------------------------
  Amazon Bedrock global cross-region inference:
  true (default) prefers availability by letting Bedrock route requests
  through its global inference profiles; set to false for data sovereignty,
  keeping all traffic within your selected aws_bedrock_regions (EU or US)
  */
  aws_bedrock_cross_region_inference_global = true

  /*
  --------------------------------------------------------------------------
  AI Services configuration
  --------------------------------------------------------------------------
  Disabled language auto-detection, which does not work properly with small
  speech samples instead of full text.
  */
  default_tts_language = "en-US"

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
  stdapi_rerank_url     = "${local.stdapi_url}/cohere/v2/rerank"
  name_prefix           = module.stdapi_ai.name_prefix
}

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
