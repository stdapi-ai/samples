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
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "playwright" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-playwright"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  container_definitions = {
    main = {
      image   = local.playwright_source_image
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

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "playwright"
}
