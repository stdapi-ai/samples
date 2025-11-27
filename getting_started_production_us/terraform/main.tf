/*
============================================================================
stdapi.ai Production Deployment - Multi-Region US
============================================================================
This configuration deploys stdapi.ai with enterprise-grade security,
monitoring, and multi-region support across US regions. Provides access
to a wider range of models for US-based workloads.

Features:
- Public ALB with HTTPS (auto-generated domain)
- IP address restriction (your current IP only)
- WAF with rate limiting and anonymous IP blocking
- API key authentication
- CloudWatch alarms and monitoring
- Interactive API documentation (/docs)
- Multi-region Bedrock support (US regions) for wider model access
============================================================================
*/

/*
----------------------------------------------------------------------------
Outputs
----------------------------------------------------------------------------
These values are displayed after deployment and can be retrieved anytime
using: terraform output <output_name>
*/

output "api_endpoint" {
  description = "Base URL for API requests (use with /v1/chat/completions)"
  value       = module.stdapi_ai.application_url
}

output "docs_url" {
  description = "Interactive API documentation (Swagger UI)"
  value       = "${module.stdapi_ai.application_url}/docs"
}

output "api_key" {
  description = "API key for authentication (keep this secret)"
  value       = module.stdapi_ai.api_key
  sensitive   = true
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
  Load Balancer Configuration
  --------------------------------------------------------------------------
  Public ALB with HTTPS (auto-generated domain from AWS)
  */
  alb_enabled = true
  alb_public  = true

  # Restrict ALB access to your current IP address only
  # This makes it safe to enable /docs and test the API
  alb_ingress_ipv4_cidrs = ["${chomp(data.http.myip.response_body)}/32"]

  # Optional: Use your custom domain instead of auto-generated ALB domain
  # Requires domain to be configured in Route53 or external DNS
  # alb_domain_name = "api.example.com"

  /*
  --------------------------------------------------------------------------
  AWS Bedrock Multi-Region Configuration
  --------------------------------------------------------------------------
  US regions for model availability
  These regions provide access to all available models
  */
  aws_bedrock_regions = [
    "us-east-1", # N. Virginia (primary)
    "us-west-2", # Oregon
    "us-east-2"  # Ohio
  ]

  /*
  Regional S3 buckets for Bedrock multimodal operations
  Required by some models for processing images, documents, etc.
  */
  aws_s3_regional_buckets = merge(
    module.bedrock_bucket_us_west_2.regional_bucket_map,
    module.bedrock_bucket_us_east_2.regional_bucket_map,
  )
  aws_s3_buckets_kms_keys_arns = [
    module.bedrock_bucket_us_west_2.kms_key_arn,
    module.bedrock_bucket_us_east_2.kms_key_arn,
  ]

  /*
  --------------------------------------------------------------------------
  Security Configuration
  --------------------------------------------------------------------------
  */
  # Generate API key for authentication
  api_key_create = true

  # Enable WAF with AWS managed rules
  alb_waf_enabled             = true
  alb_waf_rate_limit          = 2000 # Requests per 5 minutes per IP
  alb_waf_block_anonymous_ips = true # Block known anonymous IPs

  /*
  --------------------------------------------------------------------------
  Interactive Documentation
  --------------------------------------------------------------------------
  */
  # Enable Swagger UI at /docs endpoint
  # Not required in production, enabled here for testing convenience
  enable_docs = true

  /*
  --------------------------------------------------------------------------
  Monitoring Configuration
  --------------------------------------------------------------------------
  */
  # Enable CloudWatch alarms (memory, health, CPU anomaly, etc.)
  # Uncomment to enable
  # alarms_enabled = true

  # Optional: Send alarm notifications to SNS topic
  # Uncomment and set your SNS topic ARN to receive notifications
  # sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:alerts"
}

/*
----------------------------------------------------------------------------
AWS Provider Configuration
----------------------------------------------------------------------------
Main provider for primary deployment region (N. Virginia)
*/

provider "aws" {
  region = "us-east-1"
}

/*
----------------------------------------------------------------------------
Regional S3 Buckets and Providers
----------------------------------------------------------------------------
These buckets are required for Bedrock multimodal operations in each region
They store temporary data for processing images, documents, etc.
Each bucket is paired with its regional provider.
*/

module "bedrock_bucket_us_west_2" {
  source  = "stdapi-ai/stdapi-ai-s3-regional-bucket/aws"
  version = "~> 1.0"

  providers           = { aws = aws.us-west-2 }
  name_prefix         = module.stdapi_ai.name_prefix
  aws_s3_tmp_prefix   = module.stdapi_ai.aws_s3_tmp_prefix
  deletion_protection = module.stdapi_ai.deletion_protection
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

module "bedrock_bucket_us_east_2" {
  source  = "stdapi-ai/stdapi-ai-s3-regional-bucket/aws"
  version = "~> 1.0"

  providers           = { aws = aws.us-east-2 }
  name_prefix         = module.stdapi_ai.name_prefix
  aws_s3_tmp_prefix   = module.stdapi_ai.aws_s3_tmp_prefix
  deletion_protection = module.stdapi_ai.deletion_protection
}

provider "aws" {
  alias  = "us-east-2"
  region = "us-east-2"
}

/*
----------------------------------------------------------------------------
Data Sources
----------------------------------------------------------------------------
Automatically detect your current public IP address for ALB security group
*/

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}
