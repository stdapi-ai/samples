/*
============================================================================
LobeHub Deployment
============================================================================
Deploys LobeHub using ECS Fargate with stdapi.ai as the OpenAI-compatible
backend. LobeHub treats "OpenAI" as a single provider covering chat, vision,
image generation, and embeddings: there is no separate base URL/key per
feature, OPENAI_PROXY_URL and OPENAI_API_KEY cover all of it. TTS/STT has no
server-side env var: pick "OpenAI Audio" as the voice provider in the UI once
logged in (see the README).
*/

locals {
  lobehub_port         = 3210
  lobehub_source_image = "docker.io/lobehub/lobehub:${local.lobehub_image_tag}"

  # Bedrock models exposed through stdapi.ai's OpenAI-compatible surface.
  # See the README for how to change these.
  chat_model         = "anthropic.claude-sonnet-4-5-20250929-v1:0" # chat + vision (default assistant model)
  system_agent_model = "amazon.nova-micro-v1:0"                    # fast/cheap model for topic naming, translation, etc.
  embedding_model    = "cohere.embed-v4:0"                         # knowledge-base embeddings
  image_gen_model    = "stability.stable-image-core-v1:1"          # AI Image generation

  openai_model_list = join(",", [
    "-all",
    "+${local.chat_model}=Claude Sonnet 4.5<200000:vision:fc>",
    "+${local.image_gen_model}=Stable Image Core<4096:imageOutput>",
  ])

  # Turns the RSA private key in JWKS_PEM (see auth.tf) into the RS256 JWKS
  # string LobeHub wants, using the image's own Node: exporting a private key
  # in "jwk" format yields every member RFC 7518 requires. Written on one line
  # because it is passed to `node -e`, and in double quotes only, since the
  # shell below wraps it in single ones.
  jwks_script = replace(trimspace(<<-EOT
    const c = require("crypto");
    const jwk = c.createPrivateKey(process.env.JWKS_PEM).export({ format: "jwk" });
    jwk.use = "sig";
    jwk.alg = "RS256";
    jwk.kid = c.createHash("sha256").update(jwk.n).digest("hex").slice(0, 16);
    process.stdout.write(JSON.stringify({ keys: [jwk] }));
  EOT
  ), "\n", " ")
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "lobehub" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-lobehub"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  container_definitions = {
    main = {
      image = local.lobehub_source_image
      # The image's default USER (confirmed in its Dockerfile); set
      # explicitly to pass Security Hub ECS.20.
      user = "1001:1001"
      # Derives JWKS_KEY from the key pair in JWKS_PEM, then hands over to the
      # image's own entrypoint ("/bin/node" with "/app/startServer.js").
      entrypoint = ["/bin/sh", "-c"]
      command = [trimspace(<<-EOT
        export JWKS_KEY="$(/bin/node -e '${local.jwks_script}')" && exec /bin/node /app/startServer.js
      EOT
      )]
      port_mappings = {
        http = {
          container_port    = local.lobehub_port
          target_group_arns = [aws_lb_target_group.alb_lobehub.arn]
        }
      }
      health_check = {
        command      = ["CMD-SHELL", "wget -U ECS-HealthChecker -q -t=1 --spider http://127.0.0.1:${local.lobehub_port}/api/version || exit 1"]
        start_period = 30
        interval     = 30
        retries      = 3
      }
      environment = {
        ENABLED_OPENAI = "1"
        # Without this the OpenAI provider talks to api.openai.com instead of the gateway.
        OPENAI_PROXY_URL  = local.stdapi_openai_api_url
        OPENAI_MODEL_LIST = local.openai_model_list

        APP_URL          = local.lobehub_url
        INTERNAL_APP_URL = "http://localhost:${local.lobehub_port}" # Server-to-server calls (e.g. image generation); required even in single-task deployments
        # Restores the image's own default: the container runtime sets HOSTNAME
        # to the task's DNS name, and Next.js would then bind to that address
        # only, breaking the app's middleware proxy through 127.0.0.1.
        HOSTNAME = "0.0.0.0"

        /* Default models */
        DEFAULT_AGENT_CONFIG = "model=${local.chat_model};provider=openai"
        SYSTEM_AGENT         = "default=openai/${local.system_agent_model}"
        DEFAULT_FILES_CONFIG = "embedding_model=openai/${local.embedding_model}"

        /* Object storage (Amazon S3, see s3.tf) */
        # Mandatory even on AWS: the S3 client constructor throws without it.
        S3_ENDPOINT = local.s3_endpoint
        # Mandatory too: the client defaults to a hard-coded "us-east-1",
        # which signs requests for the wrong region everywhere else.
        S3_REGION = data.aws_region.current.region
        S3_BUCKET = local.s3_bucket
        # Keeps LobeHub on presigned URLs; a "public-read" ACL would also be
        # rejected outright by the bucket's "bucket owner enforced" ownership.
        S3_SET_ACL = "0"
        # Sends image bytes inline to the model provider instead of handing it
        # a presigned URL, which is a bearer credential with a lifetime.
        LLM_VISION_IMAGE_USE_BASE64 = "1"

        /* Cache / sessions (ElastiCache Valkey, see valkey.tf) */
        REDIS_PREFIX = "lobechat"
        REDIS_TLS    = "1"
      }
      secrets = {
        /* Global */
        KEY_VAULTS_SECRET = random_id.key_vaults_secret.b64_std
        AUTH_SECRET       = random_id.auth_secret.b64_std
        # Converted to the JWKS_KEY LobeHub reads by the command above.
        JWKS_PEM = tls_private_key.jwks.private_key_pem

        /* Postgres (see postgres.tf) */
        DATABASE_URL = local.postgres_url

        /* Valkey (see valkey.tf); "rediss" scheme + REDIS_TLS above enable TLS */
        REDIS_URL = "rediss://:${random_password.valkey_auth_token.result}@${local.valkey_address}/0"

        /* Amazon S3 IAM user credentials (see s3.tf) */
        S3_ACCESS_KEY_ID     = aws_iam_access_key.lobehub_s3.id
        S3_SECRET_ACCESS_KEY = aws_iam_access_key.lobehub_s3.secret

        /* stdapi.ai API key */
        OPENAI_API_KEY = module.stdapi_ai.api_key
      }
    }
  }

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "lobehub"

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
    "postgres" = {
      from_port                    = local.postgres_port
      referenced_security_group_id = module.postgres.security_group_id
    }
    "valkey" = {
      from_port                    = local.valkey_port
      referenced_security_group_id = aws_security_group.valkey.id
    }
  }
  security_group_connect_ingress = {
    "alb" = {
      from_port                    = local.lobehub_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
}
