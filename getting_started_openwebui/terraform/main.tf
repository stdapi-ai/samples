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
  openwebui_image_tag = "latest"
  searxng_image_tag   = "latest"

  /*
  Must match configured version in this file (Search "playwright==")
  https://github.com/open-webui/open-webui/blob/main/backend/requirements.txt
  */
  playwright_version = "1.57.0"
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
  security_group_id = coalesce(module.vpc.security_group_id)

  /*
  --------------------------------------------------------------------------
  Service Discovery Configuration
  --------------------------------------------------------------------------
  */
  service_discovery_dns_namespace_id = coalesce(aws_service_discovery_private_dns_namespace.internal.id)
  service_discovery_dns_name         = "stdapi-ai"

  /*
  --------------------------------------------------------------------------
  AWS Bedrock Multi-Region Configuration
  --------------------------------------------------------------------------
  Models will be accessed from these regions in order of preference

  Select between EU and US configuration.
  */
  aws_bedrock_regions = distinct([
    data.aws_region.current.name, # Current region (primary)
    # Common US regions to access almost all models
    "us-east-1", # N. Virginia
    "us-west-2", # Oregon
    "us-east-2",  # Ohio

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
  Disable global cross-region inference to keep all data within your global
  region (EU or US, based on your aws_bedrock_regions selected regions)
  This ensures AWS Bedrock only routes requests within specified regions

  Set to "false" if you need compliance/Sovereignty,
  and "true" if you prefer higher availability
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
  stdapi_openai_api_url = "http://${module.stdapi_ai.service_discovery_service_name}.${local.internal_namespace}:${module.stdapi_ai.port}/v1"
  name_prefix           = module.stdapi_ai.name_prefix
}

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
