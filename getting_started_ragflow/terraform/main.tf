/*
============================================================================
stdapi.ai with RAGFlow Deployment
============================================================================
This configuration deploys stdapi.ai as a backend service (no ALB) with
RAGFlow as the retrieval-augmented generation frontend accessible via ALB,
preconfigured with a model provider pointed at stdapi.ai.

Features:
- stdapi.ai as internal OpenAI-compatible and Cohere-compatible backend
- RAGFlow with a public ALB
- Amazon OpenSearch Service as the document and vector store
- Aurora PostgreSQL as the metadata database
- ElastiCache Valkey as the cache and task queue
- Amazon S3 as the object store, accessed through the ECS task role
- Superuser account and model provider provisioned non-interactively
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
  /*
  RAGFlow publishes x86_64 images only, so the task sets its CPU architecture
  explicitly instead of inheriting the module default. The OpenSearch document
  engine has no upstream CI coverage, which is why an exact tag is pinned
  rather than a moving one.
  */
  ragflow_image_tag = "v0.26.4"

  /*
  TLS terminator for ElastiCache. RAGFlow builds its Redis client without any
  'ssl' parameter, so it cannot speak TLS itself; socat bridges plaintext
  loopback to the encrypted ElastiCache endpoint.
  */
  socat_image_tag = "1.8.0.3"
}

/*
----------------------------------------------------------------------------
Amazon Bedrock Model Selection
----------------------------------------------------------------------------
Models bound to the RAGFlow tenant as its chat, embedding and rerank defaults
*/

locals {
  ragflow_chat_model      = "amazon.nova-lite-v1:0"
  ragflow_embedding_model = "cohere.embed-v4:0"
  ragflow_rerank_model    = "cohere.rerank-v3-5:0"
}

/*
----------------------------------------------------------------------------
Main stdapi.ai Module
----------------------------------------------------------------------------
Deploys the stdapi.ai service with all required infrastructure
*/

module "stdapi_ai" {
  source  = "stdapi-ai/stdapi-ai/aws"
  version = "~> 1.16"

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

  /*
  RAGFlow's OpenAI-API-Compatible reranker appends "/rerank" to the instance
  base URL, which lands on the Cohere-compatible v2 rerank endpoint.
  */
  stdapi_rerank_base_url = "${local.stdapi_url}/cohere/v2"

  name_prefix = module.stdapi_ai.name_prefix
}

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
