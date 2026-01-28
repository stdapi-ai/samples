/*
============================================================================
Microsoft Playwright
============================================================================
Deploys Playwright as a web scraping backend for Open WebUI
*/

locals {
  playwright_port         = 3000
  playwright_url          = "ws://${module.playwright.service_discovery_service_name}.${local.internal_namespace}:${local.playwright_port}"
  playwright_source_image = "mcr.microsoft.com/playwright:v${local.playwright_version}-noble"
  playwright_ecr_image    = "${aws_ecr_repository.playwright.repository_url}:${local.playwright_version}"
}

/*
----------------------------------------------------------------------------
Docker image & ECR Repository
----------------------------------------------------------------------------
*/

resource "aws_ecr_repository" "playwright" {
  name         = "${local.name_prefix}-playwright"
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "playwright" {
  repository = aws_ecr_repository.playwright.name
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

resource "docker_image" "playwright" {
  name = local.playwright_source_image
}

resource "docker_tag" "playwright" {
  source_image = docker_image.playwright.image_id
  target_image = local.playwright_ecr_image
}

resource "docker_registry_image" "playwright" {
  name = docker_tag.playwright.target_image
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "playwright" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.0"

  name_prefix        = "${local.name_prefix}-playwright"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  container_definitions = {
    main = {
      image   = local.playwright_ecr_image
      command = ["npx", "-y", "playwright@${local.playwright_version}", "run-server", "--port", "3000", "--host", "0.0.0.0"]
      port_mappings = {
        http = {
          container_port = local.playwright_port
        }
      }
      health_check = {
        command      = ["CMD-SHELL", "wget -U ECS-HealthChecker -q -t=1 --spider http://127.0.0.1:${local.playwright_port}/ || exit 1"]
        start_period = 30
      }
    }
  }

  service_discovery_dns_namespace_id = coalesce(aws_service_discovery_private_dns_namespace.internal.id)
  service_discovery_dns_name         = "playwright"

  depends_on = [docker_registry_image.playwright]
}
