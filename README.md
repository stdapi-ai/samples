# stdapi.ai Deployment Examples

**Production-ready Terraform examples** for deploying stdapi.ai on AWS. Each example provides complete infrastructure-as-code following AWS best practices for security, scalability, and cost optimization.

## 🎯 What is stdapi.ai?

**stdapi.ai** is an OpenAI-compatible API gateway for AWS Bedrock and AI services. Deploy any OpenAI application on AWS with no code changes—works with LangChain, Continue.dev, Open WebUI, n8n, and 1000+ tools.

- 🧠 **80+ Models** - Claude 4.6+, Nova 2, Llama 4, DeepSeek v3.2, Stable Diffusion, and more
- 🔒 **Enterprise Compliance** - Data sovereignty, GDPR/HIPAA/FedRAMP ready, AWS region controls
- 💰 **AWS Direct Pricing** - Pay-per-use with no subscriptions or markups
- ⚡ **Advanced Features** - Reasoning modes, prompt caching, guardrails, multi-region access

📚 **[Complete Documentation](https://stdapi.ai)** • 🛒 **[AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo)**

---

## 🚀 Available Examples

### 🏢 [Production](getting_started_production/)
**Single-region production deployment** with enterprise security and monitoring.

Perfect for getting started with production workloads. Includes everything needed for secure, scalable deployment in a single AWS region.

**Key Features:**
- ✅ HTTPS with auto-generated ACM certificate & Route53 DNS
- ✅ AWS WAF with rate limiting and IP filtering
- ✅ Auto-scaling (CPU, Memory, Request-based)
- ✅ CloudWatch monitoring & intelligent alarms
- ✅ API key authentication with AWS Systems Manager
- ✅ KMS encryption for all data at rest

**Best for:** Most production workloads, quick deployment, single-region requirements

---

### 🇪🇺 [Production GDPR](getting_started_production_gdpr/)
**EU multi-region deployment** with GDPR compliance and data residency controls.

Enterprise-grade deployment ensuring all data processing stays within EU regions for GDPR compliance. Supports multi-region failover across EU zones.

**Key Features:**
- ✅ Multi-region Bedrock access (EU regions only: eu-west-1, eu-west-3, eu-central-1)
- ✅ Regional S3 buckets for multimodal operations
- ✅ Data residency controls for compliance
- ✅ All production features (HTTPS, WAF, monitoring)
- ✅ GDPR-ready infrastructure

**Best for:** Enterprise deployments, GDPR compliance, EU data sovereignty requirements

---

### 🇺🇸 [Production US](getting_started_production_us/)
**US multi-region deployment** for maximum availability and performance.

Enterprise deployment leveraging multiple US regions for optimal performance and availability. Automatic cross-region failover for high availability.

**Key Features:**
- ✅ Multi-region Bedrock access (US regions: us-east-1, us-west-2, us-east-2, us-west-1)
- ✅ Regional S3 buckets for optimal performance
- ✅ Cross-region failover and load balancing
- ✅ All production features (HTTPS, WAF, monitoring)
- ✅ Maximum US availability

**Best for:** Enterprise deployments, US data residency, high availability requirements

---

### 💬 [Open WebUI](getting_started_openwebui/)
**Complete AI chat platform** with ChatGPT-like interface, web search, RAG, and multimodal capabilities.

Full-featured deployment of Open WebUI powered by stdapi.ai. Includes web search, document processing, vector storage, and all the features you'd expect from a modern AI chat interface.

**Key Features:**
- ✅ **Open WebUI** - Feature-rich ChatGPT-like interface
- ✅ **Web Search** - SearXNG integration for real-time information
- ✅ **Web Scraping** - Playwright for content extraction
- ✅ **RAG Ready** - Aurora PostgreSQL with pgvector for semantic search
- ✅ **Caching** - Valkey (Redis-compatible) for performance
- ✅ **Multimodal** - TTS, STT, image generation & editing, document processing

**Best for:** Private ChatGPT alternative, team AI assistant, complete AI chat platform

---

## 📊 Quick Comparison

Choose the example that best matches your requirements:

| Example                  | Deployment Time | Regions           | Compliance              | Best For                          |
|--------------------------|-----------------|-------------------|-------------------------|-----------------------------------|
| **🏢 Production**        | ~10 minutes     | Single region     | Standard AWS            | Most workloads, quick start       |
| **🇪🇺 Production GDPR** | ~15 minutes     | Multi-region (EU) | GDPR, EU data residency | EU enterprises, GDPR compliance   |
| **🇺🇸 Production US**   | ~15 minutes     | Multi-region (US) | US data residency       | US enterprises, high availability |
| **💬 Open WebUI**        | ~20 minutes     | Single region     | Standard AWS            | Complete chat platform, teams     |

---

## 🚦 Getting Started

### Prerequisites

Before deploying any example, you'll need:

1. **📦 AWS Marketplace Subscription** - [Subscribe to stdapi.ai](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo)
   - Free trial available
   - Provides access to hardened, production-ready container images
   - Includes commercial license for proprietary use

2. **🔧 Terraform or OpenTofu** - Install [Terraform](https://www.terraform.io/downloads) or [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5

3. **🔑 AWS Credentials** - Configure [AWS credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) with appropriate permissions

4. **🌐 Domain Name** (Production examples only) - A domain managed in Route53 for HTTPS setup

### Deployment Steps

1. **Choose your example** based on your requirements (see comparison table above)
2. **Clone this repository** (or copy the example directory)
   ```bash
   git clone https://github.com/stdapi-ai/stdapi.ai-examples.git
   cd stdapi.ai-examples
   ```
3. **Navigate to the example directory**
   ```bash
   cd getting_started_production  # or your chosen example
   ```
4. **Follow the README** in that directory for detailed deployment instructions

### What You'll Get

All examples include:
- ✅ Complete Terraform configuration with sensible defaults
- ✅ Detailed README with step-by-step instructions
- ✅ Infrastructure following AWS best practices

---

## 📚 Documentation & Resources

### Official Documentation
- **[Getting Started Guide](https://stdapi.ai/operations_getting_started/)** - Complete deployment tutorials and best practices
- **[Configuration Reference](https://stdapi.ai/operations_configuration/)** - All environment variables and settings explained
- **[API Documentation](https://stdapi.ai/api_overview/)** - Complete OpenAI-compatible API reference
- **[Use Cases & Integrations](https://stdapi.ai/use_cases/)** - Step-by-step guides for Open WebUI, n8n, Continue.dev, and more

### Product Information
- **[Licensing Guide](https://stdapi.ai/operations_licensing/)** - AGPL vs Commercial licensing explained
- **[Feature Roadmap](https://stdapi.ai/roadmap/)** - Current features and upcoming releases

### Community
- **[GitHub Repository](https://github.com/stdapi-ai/stdapi.ai)** - Source code and community discussions
- **[GitHub Issues](https://github.com/stdapi-ai/stdapi.ai/issues)** - Report bugs or request features

---

## 💡 Need Help?

### Support Options

- **📖 Documentation** - Check our comprehensive [documentation](https://stdapi.ai/) for answers
- **🐛 GitHub Issues** - [Open an issue](https://github.com/stdapi-ai/stdapi.ai/issues) for bugs or feature requests
- **💬 Community** - Join discussions on GitHub
- **🎯 Enterprise Support** - Available with [AWS Marketplace subscription](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo)

### Common Questions

**Q: Can I use this in production?**
A: Yes! These examples are production-ready with enterprise security, monitoring, and compliance features.

**Q: Which example should I start with?**
A: Start with **Production** for most use cases. Choose **Production GDPR** or **Production US** if you need multi-region or specific compliance requirements.

**Q: Do I need a domain name?**
A: Recommended for production. The ALB provides a DNS name you can use without a custom domain for testing.

---

## 📜 License

These deployment examples are licensed under the **MIT License** - see [LICENSE](LICENSE) for details.

You are free to use, modify, and distribute these examples for any purpose, including commercial use.

**Note:** The stdapi.ai container image requires an [AWS Marketplace subscription](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) and is licensed separately.

---

<div align="center">

**Ready to Deploy?**

[View Examples](#-available-examples) • [Documentation](https://stdapi.ai) • [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo)

Made with ❤️ for the AWS and AI community

</div>
