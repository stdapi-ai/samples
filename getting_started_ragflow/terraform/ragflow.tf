/*
============================================================================
RAGFlow Deployment
============================================================================
Deploys RAGFlow using ECS Fargate with stdapi.ai as the model provider,
preconfigured for chat, embeddings and reranking without any setup wizard.
*/

variable "ragflow_superuser_email" {
  type        = string
  default     = "admin@example.com"
  description = "Email address of the RAGFlow superuser, created on first start. Change this before applying if you want a real address."
}

locals {
  # nginx inside the RAGFlow image serves the web UI and proxies the API here.
  ragflow_port = 80

  # The official image, referenced directly: never built or pushed locally.
  ragflow_image = "docker.io/infiniflow/ragflow:${local.ragflow_image_tag}"
  socat_image   = "docker.io/alpine/socat:${local.socat_image_tag}"

  # RAGFlow shares the stdapi.ai bucket under its own prefix, so the sample
  # creates no second bucket and inherits the module's block-public-access,
  # versioning, SSE-KMS and TLS-only settings.
  ragflow_s3_prefix = "ragflow"

  # Delivered on a read-only S3 Files volume: the rendered configuration
  # template the entry point expands, and the tenant bootstrap script.
  ragflow_seed_files = {
    "service_conf.yaml.template" = file("${path.module}/ragflow_conf/service_conf.yaml.template")
    "bootstrap.py"               = file("${path.module}/ragflow_conf/bootstrap.py")
  }

  ragflow_environment = {
    DOC_ENGINE   = "opensearch"
    DB_TYPE      = "postgres"
    STORAGE_IMPL = "AWS_S3"

    # ECS does not set AWS_REGION, and the S3 client reads it from the
    # rendered configuration below.
    AWS_REGION = data.aws_region.current.region

    RAGFLOW_S3_BUCKET = module.stdapi_ai.bucket_id
    RAGFLOW_S3_PREFIX = local.ragflow_s3_prefix

    RAGFLOW_POSTGRES_HOST   = local.postgres_address
    RAGFLOW_POSTGRES_PORT   = tostring(local.postgres_port)
    RAGFLOW_POSTGRES_DBNAME = local.postgres_ragflow_database
    RAGFLOW_POSTGRES_USER   = local.postgres_ragflow_username

    RAGFLOW_OPENSEARCH_HOST = local.opensearch_host
    RAGFLOW_OPENSEARCH_USER = local.opensearch_username

    # Pure Python deployment: the Go server and its NATS queue stay out.
    API_PROXY_SCHEME = "python"

    # The superuser below is the only account; self-registration is closed.
    REGISTER_ENABLED           = "0"
    DEFAULT_SUPERUSER_NICKNAME = "stdapi.ai Sample"
    DEFAULT_SUPERUSER_EMAIL    = var.ragflow_superuser_email

    # The image bakes its Hugging Face mirror in; point back at the upstream
    # host so any model the deepdoc pipeline still fetches resolves.
    HF_ENDPOINT = "https://huggingface.co"

    TZ = "UTC"
  }
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
Three containers: "valkey-tls" terminates TLS towards ElastiCache, "main" is
RAGFlow itself (web server, task executor and data sync in one process tree),
and "bootstrap" binds the tenant to stdapi.ai once RAGFlow is healthy, then
exits.
*/

module "ragflow" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-ragflow"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  # RAGFlow publishes x86_64 images only.
  cpu_architecture = "X86_64"

  # deepdoc's ONNX layout and OCR models are the memory hog; the task also
  # unpacks uploaded documents to disk while parsing them.
  cpu                           = 4
  memory                        = 16384
  ephemeral_storage_size_in_gib = 50

  health_check_grace_period_seconds = 600

  # A single task. RAGFlow's web server and task executor share one process
  # tree, so a second task doubles both; and the superuser initialization and
  # the tenant bootstrap below are single-shot steps that would otherwise race
  # each other on a cold start. See "Production hardening" in the README for
  # how to scale the two roles independently.
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 1

  container_definitions = {
    valkey-tls = {
      image                     = local.socat_image
      user                      = "65534:65534"
      read_only_root_filesystem = true
      # RAGFlow builds its Redis client with no 'ssl' parameter, so it cannot
      # reach an in-transit-encrypted cluster on its own. socat accepts the
      # plaintext loopback connection and re-opens it as TLS, with the server
      # certificate verified against the system trust store.
      command = [
        "-d", "-d",
        "TCP4-LISTEN:6379,bind=127.0.0.1,reuseaddr,fork,max-children=256",
        "OPENSSL-CONNECT:${local.valkey_address},cafile=/etc/ssl/certs/ca-certificates.crt",
      ]
      health_check = {
        command      = ["CMD-SHELL", "socat -T2 /dev/null TCP4:127.0.0.1:6379 || exit 1"]
        start_period = 15
        interval     = 30
        retries      = 3
      }
    }

    main = {
      image = local.ragflow_image
      # The image entry point renders conf/service_conf.yaml.template; putting
      # the deployment's own template in its place is what carries the values
      # the template's literals would otherwise hardcode (the OpenSearch scheme
      # and port, and the whole s3 block).
      entrypoint = ["/bin/bash", "-c"]
      command = [
        "cp /seed/service_conf.yaml.template /ragflow/conf/service_conf.yaml.template && exec ./entrypoint.sh --init-superuser"
      ]
      port_mappings = {
        http = {
          container_port    = local.ragflow_port
          target_group_arns = [aws_lb_target_group.alb_ragflow.arn]
        }
      }
      health_check = {
        # Reports "ok" only when the database, the cache, the document engine
        # and the object store all answer.
        command = ["CMD-SHELL", "curl -A ECS-HealthChecker --silent --fail http://127.0.0.1:${local.ragflow_port}/api/v1/system/healthz > /dev/null || exit 1"]
        # 300 is the maximum ECS accepts; the retries below extend the tolerated
        # start-up time by another ten minutes.
        start_period = 300
        interval     = 60
        timeout      = 30
        retries      = 10
      }
      environment = local.ragflow_environment
      secrets = {
        RAGFLOW_POSTGRES_PASSWORD   = local.postgres_ragflow_password
        RAGFLOW_OPENSEARCH_PASSWORD = local.opensearch_password
        RAGFLOW_REDIS_PASSWORD      = random_password.valkey_auth_token.result
        DEFAULT_SUPERUSER_PASSWORD  = random_password.ragflow_superuser.result

        # Without it every task derives its own signing key and sessions break
        # as soon as the service runs more than one task.
        RAGFLOW_SECRET_KEY = random_password.ragflow_secret_key.result
      }
      mount_points = {
        seed = {
          container_path = "/seed"
          read_only      = true # Only ever read, never written back to.
          s3_files       = true
          s3_files_files = local.ragflow_seed_files
        }
      }
      depends_on = {
        valkey-tls = "healthy"
      }
    }

    bootstrap = {
      image      = local.ragflow_image
      essential  = false
      entrypoint = ["/bin/bash", "-c"]
      command    = ["cd /ragflow && exec python3 /seed/bootstrap.py"]
      environment = {
        DEFAULT_SUPERUSER_EMAIL = var.ragflow_superuser_email
        STDAPI_OPENAI_URL       = local.stdapi_openai_api_url
        STDAPI_RERANK_URL       = local.stdapi_rerank_base_url
        RAGFLOW_CHAT_MODEL      = local.ragflow_chat_model
        RAGFLOW_EMBEDDING_MODEL = local.ragflow_embedding_model
        RAGFLOW_RERANK_MODEL    = local.ragflow_rerank_model
      }
      secrets = {
        DEFAULT_SUPERUSER_PASSWORD = random_password.ragflow_superuser.result
        STDAPI_API_KEY             = module.stdapi_ai.api_key
      }
      mount_points = {
        seed = {
          container_path = "/seed"
          read_only      = true # Only ever read, never written back to.
          s3_files       = true
          s3_files_files = local.ragflow_seed_files
        }
      }
      depends_on = {
        main = "healthy"
      }
    }
  }

  task_role_policies = [aws_iam_policy.ragflow.arn]

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "ragflow"

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
    "postgresql" = {
      from_port                    = local.postgres_port
      referenced_security_group_id = aws_security_group.postgres.id
    }
    "valkey" = {
      from_port                    = local.valkey_port
      referenced_security_group_id = aws_security_group.valkey.id
    }
    "opensearch" = {
      from_port                    = 443
      referenced_security_group_id = aws_security_group.opensearch.id
    }
  }
  security_group_connect_ingress = {
    "alb" = {
      from_port                    = local.ragflow_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }

  depends_on = [null_resource.grant_schema_privileges]
}

/*
----------------------------------------------------------------------------
Secrets
----------------------------------------------------------------------------
*/

resource "random_password" "ragflow_superuser" {
  length  = 24
  special = false
}

resource "random_password" "ragflow_secret_key" {
  length  = 64 # RAGFlow ignores anything shorter than 32 characters
  special = false
}

/*
----------------------------------------------------------------------------
IAM Policy for S3 Access
----------------------------------------------------------------------------
RAGFlow reads no static credentials: boto3 resolves the ECS task role.
*/

data "aws_iam_policy_document" "ragflow" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${module.stdapi_ai.bucket_arn}/${local.ragflow_s3_prefix}/*"]
  }
  statement {
    # HeadBucket, which RAGFlow calls before every write, authorizes on
    # s3:ListBucket against the bucket itself.
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.stdapi_ai.bucket_arn]
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

resource "aws_iam_policy" "ragflow" {
  name        = "${local.name_prefix}-ragflow"
  description = "RAGFlow permissions"
  policy      = data.aws_iam_policy_document.ragflow.json
}

/*
----------------------------------------------------------------------------
Outputs
----------------------------------------------------------------------------
*/

output "ragflow_superuser_email" {
  description = "Email to sign in to RAGFlow with"
  value       = var.ragflow_superuser_email
}

output "ragflow_superuser_password" {
  description = "Password to sign in to RAGFlow with"
  value       = random_password.ragflow_superuser.result
  sensitive   = true
}
