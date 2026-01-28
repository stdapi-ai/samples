/*
============================================================================
Open WebUI Deployment
============================================================================
Deploys Open WebUI using ECS Fargate with stdapi.ai as the OpenAI backend
*/

locals {
  openwebui_port         = 8080
  openwebui_source_image = "ghcr.io/open-webui/open-webui:${local.openwebui_image_tag}"
  openwebui_ecr_image    = "${aws_ecr_repository.openwebui.repository_url}:${local.openwebui_image_tag}-slim"
}

/*
----------------------------------------------------------------------------
Docker image & ECR Repository
----------------------------------------------------------------------------
*/

resource "aws_ecr_repository" "openwebui" {
  name         = "${local.name_prefix}-openwebui"
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "openwebui" {
  repository = aws_ecr_repository.openwebui.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last image"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 1
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "docker_image" "openwebui" {
  name = local.openwebui_source_image
}

resource "docker_tag" "openwebui" {
  source_image = docker_image.openwebui.image_id
  target_image = local.openwebui_ecr_image
}

resource "docker_registry_image" "openwebui" {
  name = docker_tag.openwebui.target_image
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "openwebui" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.0"

  name_prefix        = "${local.name_prefix}-openwebui"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  container_definitions = {
    main = {
      image = local.openwebui_ecr_image
      port_mappings = {
        http = {
          container_port    = local.openwebui_port
          target_group_arns = [aws_lb_target_group.alb_openwebui.arn]
        }
      }
      health_check = {
        command      = ["CMD-SHELL", "curl -A ECS-HealthChecker --silent --fail http://127.0.0.1:${local.openwebui_port}/health | jq -ne 'input.status == true' || exit 1"]
        start_period = 30
        interval     = 30
        retries      = 3
      }
      environment = {
        ENABLE_PERSISTENT_CONFIG = "true" # Ensure environment variables configuration is always used
        CORS_ALLOW_ORIGIN        = local.openwebui_url
        USER_AGENT               = "${local.name_prefix}/openwebui" # Required to avoid warnings

        /* Logging */
        ENABLE_AUDIT_STDOUT = "true" # Output to CloudWatch

        # Can be enabled to increase verbosity
        # AUDIT_LOG_LEVEL  = "REQUEST_RESPONSE"
        # GLOBAL_LOG_LEVEL = "DEBUG"

        /* Common models */
        OPENAI_API_BASE_URL = local.stdapi_openai_api_url
        TASK_MODEL_EXTERNAL = "amazon.nova-micro-v1:0"

        /* RAG */
        RAG_EMBEDDING_ENGINE      = "openai"
        RAG_OPENAI_API_BASE_URL   = local.stdapi_openai_api_url
        RAG_EMBEDDING_MODEL       = "cohere.embed-v4:0"
        VECTOR_DB                 = "pgvector" # Aurora PostgreSQL with Vector extension
        PGVECTOR_CREATE_EXTENSION = "false"    # Already initialized

        /* Image generation */
        ENABLE_IMAGE_GENERATION    = "true"
        IMAGE_GENERATION_ENGINE    = "openai"
        IMAGES_OPENAI_API_BASE_URL = local.stdapi_openai_api_url
        IMAGE_GENERATION_MODEL     = "stability.stable-image-core-v1:1"

        /* Image editing */
        ENABLE_IMAGE_EDIT               = "true"
        IMAGE_EDIT_ENGINE               = "openai"
        IMAGES_EDIT_OPENAI_API_BASE_URL = local.stdapi_openai_api_url
        IMAGE_EDIT_MODEL                = "stability.stable-image-control-structure-v1:0"

        /* Speech to Text */
        AUDIO_STT_ENGINE              = "openai"
        AUDIO_STT_OPENAI_API_BASE_URL = local.stdapi_openai_api_url
        AUDIO_STT_MODEL               = "amazon.transcribe"

        /* Text to speech */
        AUDIO_TTS_ENGINE              = "openai"
        AUDIO_TTS_OPENAI_API_BASE_URL = local.stdapi_openai_api_url
        AUDIO_TTS_MODEL               = "amazon.polly-neural"

        /* Web search */
        ENABLE_WEB_SEARCH = "true"
        WEB_SEARCH_ENGINE = "searxng"
        SEARXNG_QUERY_URL = local.searxng_url

        /* Web scraping */
        WEB_LOADER_ENGINE = "playwright"
        PLAYWRIGHT_WS_URL = local.playwright_url

        /* Databases - Redis/Valkey */
        REDIS_URL                = "redis://${local.valkey_address}/0"
        REDIS_CLUSTER            = "false" # Set to true when using ElastiCache Valkey with cluster_mode = "enabled"
        WEBSOCKET_MANAGER        = "redis"
        WEBSOCKET_REDIS_URL      = "redis://${local.valkey_address}/1"
        ENABLE_WEBSOCKET_SUPPORT = "true"

        /* S3 Storage */
        STORAGE_PROVIDER = "s3"
        S3_BUCKET_NAME   = module.stdapi_ai.bucket_id
        S3_REGION_NAME   = data.aws_region.current.id
        S3_KEY_PREFIX    = "openwebui/"

        /* Avoid downloading external models */
        OFFLINE_MODE                    = "true"
        HF_HUB_OFFLINE                  = "1"
        RAG_EMBEDDING_MODEL_AUTO_UPDATE = "false"
        RAG_RERANKING_MODEL_AUTO_UPDATE = "false"
        WHISPER_MODEL_AUTO_UPDATE       = "false"
        ENABLE_OLLAMA_API               = "false" # Not available, disabled to avoid errors

        /* Performance - Models caching */
        ENABLE_BASE_MODELS_CACHE = "true"
        MODELS_CACHE_TTL         = "3600"

        /* Performance - Database */
        # See: https://docs.openwebui.com/troubleshooting/multi-replica#7-optimizing-database-performance
        DATABASE_ENABLE_SESSION_SHARING = "true"
        DATABASE_POOL_SIZE              = "15"
        DATABASE_POOL_MAX_OVERFLOW      = "20"
        DATABASE_POOL_RECYCLE           = "900" # Allow faster Aurora serverless v2 scale in

        /* Performance - images */
        ENABLE_CHAT_RESPONSE_BASE64_IMAGE_URL_CONVERSION = "true"
      }
      secrets = {
        /* Global */
        WEBUI_SECRET_KEY = random_password.openwebui_secret_key.result

        /* Database URLs with passwords */
        DATABASE_URL    = local.postgres_url_main
        PGVECTOR_DB_URL = local.postgres_url_vector

        /* stdapi.ai API key */
        OPENAI_API_KEY             = module.stdapi_ai.api_key
        RAG_OPENAI_API_KEY         = module.stdapi_ai.api_key
        IMAGES_OPENAI_API_KEY      = module.stdapi_ai.api_key
        IMAGES_EDIT_OPENAI_API_KEY = module.stdapi_ai.api_key
        AUDIO_STT_OPENAI_API_KEY   = module.stdapi_ai.api_key
        AUDIO_TTS_OPENAI_API_KEY   = module.stdapi_ai.api_key
      }
      mount_points = {
        data = {
          container_path = "/app/backend/data"
          efs            = true
        }
        nltk_data = {
          container_path = "/root/nltk_data"
          efs            = true
        }
      }
    }
  }
  task_role_policies = [aws_iam_policy.openwebui.arn]

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
    "searxng" = {
      from_port                    = local.searxng_port
      referenced_security_group_id = module.searxng.security_group_id
    }
    "playwright" = {
      from_port                    = local.playwright_port
      referenced_security_group_id = module.playwright.security_group_id
    }
    "valkey" = {
      from_port                    = local.valkey_port
      referenced_security_group_id = aws_security_group.valkey.id
    }
    "postgresql" = {
      from_port                    = local.postgres_port
      referenced_security_group_id = aws_security_group.postgres.id
    }
  }
  security_group_connect_ingress = {
    "alb" = {
      from_port                    = local.openwebui_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
  security_group_rules_egress = {
    # HTTP required for "nltk" download (Playwright dependency)
    # https://github.com/open-webui/open-webui/blob/main/backend/start.sh#L14
    "internet_ipv4_http" = {
      from_port = 80
      cidr_ipv4 = "0.0.0.0/0"
    }
    "internet_ipv6_http" = {
      from_port = 80
      cidr_ipv6 = "::/0"
    }
  }

  depends_on = [
    docker_registry_image.openwebui,
    null_resource.grant_vector_schema_privileges,
  ]
}

resource "random_password" "openwebui_secret_key" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
IAM Policy for S3 Access
----------------------------------------------------------------------------
*/

data "aws_iam_policy_document" "openwebui" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "${module.stdapi_ai.bucket_arn}/openwebui/*",
      module.stdapi_ai.bucket_arn
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = [module.stdapi_ai.kms_key_arn]
  }
}

resource "aws_iam_policy" "openwebui" {
  name        = "${local.name_prefix}-openwebui"
  description = "Open WebUI permissions"
  policy      = data.aws_iam_policy_document.openwebui.json
}
