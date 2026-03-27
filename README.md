# stdapi.ai Deployment Examples

**Production-ready Terraform examples** for deploying [stdapi.ai](https://stdapi.ai) — an OpenAI & Anthropic compatible API gateway for AWS Bedrock. **14-day free trial included.**

[Start 14-Day Free Trial](https://stdapi.ai/operations_getting_started/) · [Documentation](https://stdapi.ai) · [GitHub Repository](https://github.com/stdapi-ai/stdapi.ai)

---

## Available Examples

### 🏢 [Production](getting_started_production/)
**Single-region production deployment** with enterprise security and monitoring.

Perfect for getting started with production workloads. Includes everything needed for secure, scalable deployment in a single AWS region.

**Key Features:**
- HTTPS with auto-generated ACM certificate & Route53 DNS
- AWS WAF with rate limiting and IP filtering
- Auto-scaling (CPU, Memory, Request-based)
- CloudWatch monitoring & intelligent alarms
- API key authentication with AWS Systems Manager
- KMS encryption for all data at rest

**Best for:** Most production workloads, quick deployment, single-region requirements

---

### 🇪🇺 [Production GDPR](getting_started_production_gdpr/)
**EU multi-region deployment** with GDPR compliance and data residency controls.

Enterprise-grade deployment ensuring all data processing stays within EU regions. Supports multi-region failover across EU zones.

**Key Features:**
- Multi-region Bedrock access (EU regions only: eu-west-1, eu-west-3, eu-central-1)
- Regional S3 buckets for multimodal operations
- Data residency controls for compliance
- All production features (HTTPS, WAF, monitoring)
- GDPR-ready infrastructure

**Best for:** Enterprise deployments, GDPR compliance, EU data sovereignty requirements

---

### 🇺🇸 [Production US](getting_started_production_us/)
**US multi-region deployment** for maximum availability and performance.

Enterprise deployment leveraging multiple US regions for optimal performance and availability. Automatic cross-region failover for high availability.

**Key Features:**
- Multi-region Bedrock access (US regions: us-east-1, us-west-2, us-east-2, us-west-1)
- Regional S3 buckets for optimal performance
- Cross-region failover and load balancing
- All production features (HTTPS, WAF, monitoring)
- Maximum US availability

**Best for:** Enterprise deployments, US data residency, high availability requirements

---

### 💬 [Open WebUI](getting_started_openwebui/)
**Complete AI chat platform** with ChatGPT-like interface, web search, RAG, and multimodal capabilities.

Full-featured deployment of Open WebUI powered by stdapi.ai. Includes web search, document processing, vector storage, and all the features you'd expect from a modern AI chat interface.

**Key Features:**
- **Open WebUI** — Feature-rich ChatGPT-like interface
- **Web Search** — SearXNG integration for real-time information
- **Web Scraping** — Playwright for content extraction
- **RAG Ready** — Aurora PostgreSQL with pgvector for semantic search
- **Caching** — Valkey (Redis-compatible) for performance
- **Multimodal** — TTS, STT, image generation & editing, document processing

**Best for:** Private ChatGPT alternative, team AI assistant, complete AI chat platform

---

## Quick Comparison

| Example | Deployment Time | Regions | Compliance | Best For |
|---|---|---|---|---|
| **Production** | ~10 minutes | Single region | Standard AWS | Most workloads, quick start |
| **Production GDPR** | ~15 minutes | Multi-region (EU) | GDPR, EU data residency | EU enterprises, GDPR compliance |
| **Production US** | ~15 minutes | Multi-region (US) | US data residency | US enterprises, high availability |
| **Open WebUI** | ~20 minutes | Single region | Standard AWS | Complete chat platform, teams |

---

## Getting Started

### Prerequisites

1. **AWS Marketplace Subscription** — [Start 14-day free trial](https://stdapi.ai/operations_getting_started/) (includes hardened container images and commercial license)
2. **Terraform or OpenTofu** — Install [Terraform](https://www.terraform.io/downloads) or [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5
3. **AWS Credentials** — Configure [AWS credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) with appropriate permissions
4. **Domain Name** (production examples only) — A domain managed in Route53 for HTTPS setup

### Deploy

```bash
git clone https://github.com/stdapi-ai/stdapi.ai-examples.git
cd stdapi.ai-examples/getting_started_production  # or your chosen example
```

Follow the README in that directory for step-by-step instructions.

---

## License

These deployment examples are licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

The stdapi.ai container image requires a separate [AWS Marketplace subscription](https://stdapi.ai/operations_getting_started/).

---

<div align="center">

**Ready to deploy 80+ AI models on AWS?**

[Start 14-Day Free Trial](https://stdapi.ai/operations_getting_started/) · [Full Documentation](https://stdapi.ai)

</div>
