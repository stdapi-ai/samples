/*
============================================================================
SearXNG Search Engine
============================================================================
Deploys SearXNG as a web search backend for Open WebUI
*/

locals {
  searxng_port      = 8080
  searxng_url       = "http://${module.searxng.service_discovery_service_name}.${local.internal_namespace}:${local.searxng_port}/search?q=<query>"
  searxng_ecr_image = "${aws_ecr_repository.searxng.repository_url}:${local.searxng_image_tag}"
}

/*
----------------------------------------------------------------------------
Docker image & ECR Repository
----------------------------------------------------------------------------
*/

resource "aws_ecr_repository" "searxng" {
  name         = "${local.name_prefix}-searxng"
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "searxng" {
  repository = aws_ecr_repository.searxng.name
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

resource "docker_image" "searxng" {
  name = local.searxng_ecr_image
  build {
    context    = "${path.module}/searxng"
    dockerfile = "Dockerfile"
    build_args = {
      SEARXNG_VERSION = local.searxng_image_tag
    }
  }
}

resource "docker_registry_image" "searxng" {
  name = docker_image.searxng.name
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "searxng" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.0"

  name_prefix        = "${local.name_prefix}-searxng"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  container_definitions = {
    main = {
      image = local.searxng_ecr_image
      port_mappings = {
        http = {
          container_port = local.searxng_port
        }
      }
      health_check = {
        command      = ["CMD-SHELL", "wget -U ECS-HealthChecker -q -t=1 --spider http://127.0.0.1:${local.searxng_port}/ || exit 1"]
        start_period = 30
      }
      environment = {
        SEARXNG_PORT = tostring(local.searxng_port)
      }
      secrets = {
        SEARXNG_VALKEY_URL = "valkey://${local.valkey_address}/2"
        SEARXNG_SECRET     = random_password.searxng_secret_key.result
      }
    }
  }

  service_discovery_dns_namespace_id = coalesce(aws_service_discovery_private_dns_namespace.internal.id)
  service_discovery_dns_name         = "searxng"

  security_group_connect_egress = {
    "valkey" = {
      from_port                    = local.valkey_port
      referenced_security_group_id = aws_security_group.valkey.id
    }
  }

  depends_on = [docker_registry_image.searxng]
}

resource "random_password" "searxng_secret_key" {
  length  = 32
  special = false
}
