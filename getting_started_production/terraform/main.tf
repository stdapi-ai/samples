/*
============================================================================
stdapi.ai Production Deployment - Single Region
============================================================================
This configuration deploys stdapi.ai with production-grade security and
monitoring in a single AWS region. Ideal for most production workloads.

Features:
- Public ALB with HTTPS (auto-generated domain)
- IP address restriction (your current IP only)
- WAF with rate limiting and anonymous IP blocking
- API key authentication
- CloudWatch alarms and monitoring
- Interactive API documentation (/docs)
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
Data Sources
----------------------------------------------------------------------------
Automatically detect your current public IP address for ALB security group
*/

data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}
