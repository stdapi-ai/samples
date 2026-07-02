/*
============================================================================
stdapi.ai Production Deployment - Multi-Region GDPR Compliant
============================================================================
This configuration deploys stdapi.ai with enterprise-grade security,
monitoring, and GDPR compliance across EU regions. All data processing
stays within the EU, with no global cross-region inference.

Features:
- Public ALB with HTTPS (auto-generated domain)
- IP address restriction (your current IP only)
- WAF with rate limiting and anonymous IP blocking
- API key authentication
- Optional CloudWatch alarms and monitoring
- Interactive API documentation (/docs)
- Multi-region Bedrock support (EU only) for wider model access
- Regional data residency for GDPR compliance
- No global cross-region inference
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
  EU regions for model availability and redundancy
  Models will be accessed from these regions in order of preference
  */
  aws_bedrock_regions = [
    "eu-west-3",    # Paris (primary)
    "eu-west-1",    # Ireland
    "eu-central-1", # Frankfurt
    "eu-north-1"    # Stockholm
  ]

  # Regional S3 buckets are created automatically for each region in aws_bedrock_regions.

  /*
  --------------------------------------------------------------------------
  GDPR Compliance Configuration
  --------------------------------------------------------------------------
  Disable global cross-region inference to keep all data within EU
  This ensures AWS Bedrock only routes requests within specified EU regions
  */
  aws_bedrock_cross_region_inference_global = false

  /*
  --------------------------------------------------------------------------
  AI Services Regional Configuration
  --------------------------------------------------------------------------
  AWS Comprehend is not available in eu-west-3, use eu-west-1 instead
  Required for features that use AWS Comprehend
  */
  aws_comprehend_region = "eu-west-1"

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
  # sns_topic_arn = "arn:aws:sns:eu-west-3:123456789012:alerts"
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
