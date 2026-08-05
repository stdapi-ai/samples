# stdapi.ai Deployment Examples

**Production-ready Terraform examples** for deploying [stdapi.ai](https://stdapi.ai) — an OpenAI, Anthropic & Cohere compatible API gateway that runs in your own AWS account, in front of Amazon Bedrock and the AWS AI services (Polly, Transcribe, Comprehend). Not just chat: images, video, audio, files, embeddings, moderation and reranking. **14-day free trial included.**

[Start 14-Day Free Trial](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) · [Documentation](https://stdapi.ai/operations_getting_started/) · [GitHub Repository](https://github.com/stdapi-ai/stdapi.ai)

---

## Available Examples

### 🏢 [Production](getting_started_production/)
**Single-region production deployment** with hardened security defaults and optional monitoring.

Perfect for getting started with production workloads. Includes everything needed for secure, scalable deployment in a single AWS region.

**Key Features:**
- HTTPS with auto-generated ALB domain (or custom domain with Route53)
- Auto-scaling (CPU, Memory, Request-based)
- KMS encryption for all data at rest
- API key authentication
- Optional WAF protection and CloudWatch alarms

**Best for:** Most production workloads, quick deployment, single-region requirements

---

### 🇪🇺 [Production GDPR](getting_started_production_gdpr/)
**EU multi-region deployment** with EU data residency controls.

Deployment that keeps model processing within the EU regions you enable. Eligible failures retry in another enabled EU region.

**Key Features:**
- Multi-region Bedrock access (4 EU regions: eu-west-3 Paris, eu-west-1 Ireland, eu-central-1 Frankfurt, eu-north-1 Stockholm)
- Regional S3 buckets for multimodal operations
- Region allow-list with global cross-region inference disabled
- All production features (HTTPS, WAF)
- Data residency controls for an EU-only processing footprint

**Best for:** Enterprise deployments, EU data residency and data sovereignty requirements

---

### 🇺🇸 [Production US](getting_started_production_us/)
**US multi-region deployment** for maximum availability and performance.

Enterprise deployment leveraging multiple US regions for performance and availability. Eligible failures retry in another enabled US region.

**Key Features:**
- Multi-region Bedrock access (3 US regions: us-east-1, us-west-2, us-east-2)
- Regional S3 buckets for optimal performance
- Retry across enabled regions, each with its own Bedrock quota
- All production features (HTTPS, WAF)
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

### 🔗 [n8n](getting_started_n8n/)
**Preconfigured workflow automation** with a credential and thirteen sample workflows already in place.

Deployment of n8n powered by stdapi.ai, with an owner account provisioned non-interactively and one runnable sample workflow per stdapi.ai route family imported automatically on first start.

**Key Features:**

- **n8n** — Visual workflow automation, backed by Aurora PostgreSQL
- **Pre-imported credential and workflows** — OpenAI- and Anthropic-compatible credentials plus 13 sample workflows, seeded on first boot
- **Non-interactive owner account** — No signup screen to click through
- **No local image build** — The official `n8nio/n8n` image is pulled directly from Docker Hub

**Best for:** Trying stdapi.ai's full route surface through n8n's node library, no manual setup

---

### 🪽 [Hermes Agent](getting_started_hermes/)
**Autonomous agent on Amazon Bedrock**, with its gateway and dashboard preconfigured against stdapi.ai.

Deployment of [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research), with `config.yaml` seeded on first boot and no manual editing before the first run.

**Key Features:**

- **Hermes gateway + dashboard** — OpenAI-compatible API and monitoring UI, dashboard behind HTTP Basic Auth
- **Preconfigured `config.yaml`** — stdapi.ai URL and API key already filled in
- **Persistent state** — Config, sessions, memories, and skills on EFS
- **No local image build** — The image is pulled anonymously from Docker Hub
- **ECS Exec** — Shell into the container or drive Hermes' interactive CLI directly

**Best for:** Trying an autonomous agent loop against Bedrock models with zero API-key hunting

---

### 🏠 [Home Assistant + wyoming-openai](getting_started_home_assistant/)
**Voice assistant on AWS**, bridging Home Assistant's Assist pipeline to Amazon Transcribe and Polly through stdapi.ai.

Deployment of Home Assistant with [wyoming-openai](https://github.com/roryeckel/wyoming_openai) as a same-task sidecar.

**Key Features:**

- **Home Assistant** — Config on a persistent EFS volume
- **wyoming-openai** — Bridges Assist's Wyoming protocol to stdapi.ai's OpenAI-compatible audio routes
- **Amazon Transcribe + Polly** — Speech-to-text and text-to-speech through stdapi.ai
- **No local image build** — Both images are pulled directly from ghcr.io

**Best for:** Assist voice through AWS AI services — as a cloud-hosted trial, or as the AWS half of a Home Assistant you run at home

---

## Quick Comparison

### Gateway deployments

| Example | Deployment Time | Regions | Data residency | Best For |
|---|---|---|---|---|
| **Production** | ~10 minutes | Single region | The region you deploy in | Most workloads, quick start |
| **Production GDPR** | ~15 minutes | Multi-region (EU) | EU regions only, global cross-region inference disabled | EU enterprises, EU data residency |
| **Production US** | ~15 minutes | Multi-region (US) | US regions only | US enterprises, high availability |

> Region retry covers eligible throttling and availability failures. Streaming requests can only retry before the stream opens, and asynchronous jobs stay in the region that accepted them. Each region you enable adds its own Bedrock quota.

### Application examples

Each of these deploys stdapi.ai in a single region, with the application in front of it.

| Example | Deployment Time | Backing services | Best For |
|---|---|---|---|
| **Open WebUI** | ~20 minutes | Aurora PostgreSQL, Valkey, S3 | Complete chat platform, teams |
| **n8n** | ~15-20 minutes | Aurora PostgreSQL | Workflow automation over the full route surface |
| **Hermes Agent** | ~5 minutes | EFS | An autonomous agent loop on Bedrock |
| **Home Assistant** | ~5-10 minutes | EFS | Assist voice through Amazon Transcribe and Polly |

---

## Getting Started

### Prerequisites

1. **AWS Marketplace Subscription** — [Start 14-day free trial](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) (includes hardened container images and commercial license)

   Want to evaluate first, for free? The AGPL-3.0 **Community Edition** image `ghcr.io/stdapi-ai/stdapi.ai-community:latest` exposes the same API at no cost — see [Run locally with Docker](https://stdapi.ai/operations_getting_started_local/). The commercial difference is hardening, support and license rights, not endpoints.
2. **Terraform or OpenTofu** — Install [Terraform](https://www.terraform.io/downloads) or [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5
3. **AWS Credentials** — Configure [AWS credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) with appropriate permissions
4. **Domain Name** (optional) — A domain managed in Route53, to serve HTTPS from your own name instead of the auto-generated ALB domain. Set `alb_domain_name` in `main.tf` to use it.

### Cost

The stdapi.ai license is **$0.10 per container-hour** on the AWS Marketplace (**$0.09** through a private offer), and **$0** for the Community Edition image. These examples keep the module defaults, which run **one task per availability zone** — so a three-AZ region runs three tasks, about **$216/month** in license, and six in us-east-1. ALB, NAT gateways, Fargate and KMS are billed separately by AWS. Amazon Bedrock usage is billed to you directly by AWS with **0% markup**.

### Deploy

```bash
git clone https://github.com/stdapi-ai/samples.git
cd samples/getting_started_production  # or your chosen example
```

> **No git?** Download the ZIP instead:
> ```bash
> curl -L https://github.com/stdapi-ai/samples/archive/refs/heads/main.zip -o samples.zip
> unzip samples.zip && cd samples-main/getting_started_production
> ```

Follow the README in that directory for step-by-step instructions.

---

## License

These deployment examples are licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

The hardened stdapi.ai container image requires a separate [AWS Marketplace subscription](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo). The AGPL-3.0 [Community Edition](https://stdapi.ai/operations_getting_started_local/) image is free.

---

<div align="center">

**Ready to deploy 100+ AI models on AWS?**

[Start 14-Day Free Trial](https://aws.amazon.com/marketplace/pp/prodview-su2dajk5zawpo) · [Full Documentation](https://stdapi.ai/operations_getting_started/)

</div>
