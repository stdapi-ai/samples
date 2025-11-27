# Production Deployment - Multi-Region US

Enterprise-ready deployment with multi-region Bedrock support across US regions for maximum availability.

**See full documentation:** [Getting Started Guide](https://stdapi.ai/operations_getting_started/)

## Prerequisites

1. **AWS Marketplace Subscription**: [Subscribe to stdapi.ai](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) - 14-day free trial
2. **Terraform or OpenTofu**: Install [Terraform](https://www.terraform.io/downloads) or [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5
3. **AWS Credentials**: Configure your credentials
   ```bash
   aws sso login --profile your-profile
   ```

## Deployment

```bash
cd terraform
terraform init
terraform apply
```

Get your API credentials:
```bash
terraform output -raw api_key
terraform output api_endpoint
terraform output docs_url
```

## What You Get

- Multi-region Bedrock support (3 US regions: N. Virginia, Oregon, Ohio)
- Access to all available models across regions
- Regional S3 buckets for multimodal operations
- HTTPS with automatic SSL certificate (auto-generated domain)
- WAF protection with rate limiting and anonymous IP blocking
- CloudWatch alarms and monitoring
- Auto-scaling and API key authentication
- Interactive API documentation at `/docs`
- IP-restricted access (your IP only)

## Making Your First API Call

**Wait for service to be ready**: After deployment, the ECS service needs a few minutes to start. The ALB will return `503 Service Unavailable` until the service is healthy. Wait 2-3 minutes before testing.

Test your deployment:

```bash
curl -X POST "$(terraform output -raw api_endpoint)/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(terraform output -raw api_key)" \
  -d '{
    "model": "amazon.nova-micro-v1:0",
    "messages": [{"role": "user", "content": "Hello! Tell me a joke."}]
  }'
```

Or visit the interactive documentation:
```bash
open "$(terraform output -raw docs_url)"
```

## When to Use This Example

- Access to all available models across US regions
- Multi-region Bedrock with multimodal features
- Enterprise deployments requiring US multi-region setup

For simpler single-region deployment, see the `getting_started_production` example.

## Security

### IP Address Restriction

Access is restricted to your current IP address:
- Your public IP is automatically detected during deployment
- If your IP changes, run `terraform apply` to update access

**To allow multiple IPs**, edit `alb_ingress_ipv4_cidrs` in `main.tf`:
```hcl
alb_ingress_ipv4_cidrs = [
  "203.0.113.0/32",  # Your office IP
  "198.51.100.0/32"  # Additional IP
]
```

## Customization

The configuration works out of the box with US regions. To customize (optional):

- **Custom domain**: Uncomment `alb_domain_name` in `main.tf`
- **SNS notifications**: Uncomment `sns_topic_arn` in `main.tf`
- **Different regions**: Edit `aws_bedrock_regions` and provider configurations in `main.tf`
- **Disable /docs**: Set `enable_docs = false` in `main.tf`

## Cleanup

To delete all resources and stop incurring charges:

```bash
cd terraform
terraform destroy
```

**Note**: This will permanently delete all resources including regional S3 buckets and data.

## Version Compatibility

- Terraform/OpenTofu >= 1.5
- stdapi.ai Terraform module ~> 1.0
- AWS Provider >= 4.0

## Additional Resources

- [Getting Started Guide](https://stdapi.ai/operations_getting_started/)
- [Configuration Guide](https://stdapi.ai/operations_configuration/)
- [Terraform Module Documentation](https://github.com/stdapi-ai/terraform-aws-stdapi-ai)
- [API Reference](https://stdapi.ai/api_overview/)
