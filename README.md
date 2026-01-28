# stdapi.ai Deployment Examples

Ready-to-use examples for deploying stdapi.ai on AWS with production-ready configurations.

## Available Examples

### 🏢 [Production](getting_started_production/)
Production-grade deployment with HTTPS, WAF, and monitoring. Single region deployment.

- **Best for**: Most production workloads, getting started
- **Features**: HTTPS with auto-generated domain, WAF, auto-scaling, optional CloudWatch alarms, API authentication

### 🇪🇺 [Production GDPR](getting_started_production_gdpr/)
Enterprise deployment with multi-region support and GDPR compliance (EU regions).

- **Best for**: Enterprise deployments, GDPR compliance, EU multi-region requirements
- **Features**: Multi-region Bedrock (EU), GDPR-compliant, regional S3 buckets, optional CloudWatch alarms

### 🇺🇸 [Production US](getting_started_production_us/)
Enterprise deployment with multi-region support across US regions.

- **Best for**: Enterprise deployments, US multi-region requirements, maximum US availability
- **Features**: Multi-region Bedrock (US), regional S3 buckets, optional CloudWatch alarms

### 💬 [Open WebUI](getting_started_openwebui/)
ChatGPT-like web interface powered by stdapi.ai with integrated search, RAG, and multimodal capabilities.

Open WebUI is an extensible, feature-rich, and user-friendly self-hosted AI chat interface. This deployment includes stdapi.ai backend, SearXNG for web search, Playwright for web scraping, and RAG-ready storage.

- **Best for**: Complete AI chat platform with ChatGPT-like UI, TTS, STT, image generation & editing, web search and RAG
- **Features**: Open WebUI interface, web search (SearXNG), web scraping (Playwright), vector storage (Aurora PostgreSQL + pgvector), caching (Valkey)

## Choosing the Right Example

| Example                             | Best For                         | Key Features                                      |
|-------------------------------------|----------------------------------|---------------------------------------------------|
| **getting_started_production**      | Most production workloads        | Single region, full security, optional monitoring |
| **getting_started_production_gdpr** | Enterprise, GDPR compliance (EU) | Multi-region EU, GDPR-compliant                   |
| **getting_started_production_us**   | Enterprise, US multi-region      | Multi-region US, high availability                |
| **getting_started_openwebui**       | Open WebUI chat platform         | Fully featured ChatGPT like web interface         |

## Prerequisites

**AWS Marketplace Subscription**: [Subscribe to stdapi.ai](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) - 14-day free trial (required for container access)

Each example has its own deployment requirements. See the individual example README for details.

## Getting Started

1. Choose an example based on your needs
2. Navigate to the example directory
3. Follow the README instructions in that directory

## License

These examples are licensed under the MIT License. See [LICENSE](LICENSE) for details.

You are free to use, modify, and distribute these examples for any purpose, including commercial use.

## Additional Resources

- [Getting Started Guide](https://stdapi.ai/operations_getting_started/)
- [stdapi.ai Documentation](https://stdapi.ai/)
- [API Reference](https://stdapi.ai/api_overview/)
- [Configuration Guide](https://stdapi.ai/operations_configuration/)

## Support

For issues or questions:
- Open an issue on GitHub
- Check the [documentation](https://stdapi.ai/)

## Contributing

Contributions are welcome! If you have improvements or additional examples:
1. Fork the repository
2. Create your feature branch
3. Submit a pull request
