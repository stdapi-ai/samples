/*
============================================================================
Hermes Agent Deployment
============================================================================
Deploys Hermes Agent (Nous Research) using ECS Fargate, preconfigured to
use stdapi.ai/Amazon Bedrock as its model backend.

No image is built or pushed locally: the image is referenced directly from
Docker Hub (docker.io/nousresearch/hermes-agent) and pulled by Fargate over
the VPC's internet egress, with no credential. The init container reuses the
same image.
*/

locals {
  hermes_image = "docker.io/nousresearch/hermes-agent:v2026.8.3"

  hermes_gateway_port   = 8642
  hermes_dashboard_port = 9119

  # Runtime "hermes" user baked into the image (useradd -u 10000 -m -d /opt/data hermes
  # in the upstream Dockerfile); EFS/S3 Files POSIX users must match it so the
  # non-root runtime user can read/write its own data.
  hermes_uid = 10000
  hermes_gid = 10000

  # Bedrock model routed through stdapi.ai. Change to any Bedrock model ID your
  # account has access to (see the README's Customization section).
  hermes_model = "anthropic.claude-haiku-4-5-20251001-v1:0"
  # Hermes otherwise asks for more output tokens than the model allows and every
  # turn fails with "maximum tokens ... exceeds the model limit". Update this
  # alongside hermes_model.
  hermes_model_max_tokens = 64000

  hermes_dashboard_username = "admin"
}

/*
----------------------------------------------------------------------------
Dashboard Authentication
----------------------------------------------------------------------------
The dashboard refuses to bind non-loopback without an auth provider
configured (June 2026 hardening). HTTP Basic Auth is the simplest provider
that works unattended, with no external identity provider required.
*/

resource "random_password" "hermes_dashboard_password" {
  length  = 32
  special = false
}

resource "random_password" "hermes_dashboard_secret" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
Gateway API Authentication
----------------------------------------------------------------------------
The OpenAI-compatible API server on port 8642 is disabled by default and,
even once enabled, only binds to loopback unless a key is set (upstream
"opening a port on an internet facing machine" guard). Both are required to
reach it through the ALB. See https://hermes-agent.nousresearch.com/docs/user-guide/docker/
*/

resource "random_password" "hermes_api_server_key" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "hermes" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-hermes"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS (Docker Hub image pull)

  cpu    = 2
  memory = 4096

  enable_execute_command            = true # Required for "aws ecs execute-command" (shell, Hermes interactive CLI)
  health_check_grace_period_seconds = 60

  container_definitions = {
    /*
    Init container: copies config.yaml from the read-only S3 Files mount
    into /opt/data (EFS) on first boot only, so edits made after deployment
    survive every redeploy. Bypasses the image's own entrypoint (which needs
    root to perform its own privilege drop), so running as the non-root
    "hermes" user with a read-only root filesystem is safe here.
    */
    init = {
      image                     = local.hermes_image
      essential                 = false
      user                      = "${local.hermes_uid}:${local.hermes_gid}"
      entrypoint                = ["sh", "-c"]
      command                   = ["if [ ! -f /opt/data/config.yaml ]; then cp /mnt/seed/config.yaml /opt/data/config.yaml; fi"]
      read_only_root_filesystem = true
      mount_points = {
        seed = {
          container_path = "/mnt/seed"
          read_only      = true
          s3_files       = true
          s3_files_posix_user = {
            uid = local.hermes_uid
            gid = local.hermes_gid
          }
          s3_files_files = {
            "config.yaml" = templatefile("${path.module}/hermes/config.yaml.tftpl", {
              model      = local.hermes_model
              max_tokens = local.hermes_model_max_tokens
              base_url   = local.stdapi_openai_api_url
              api_key    = module.stdapi_ai.api_key
            })
          }
        }
        data = {
          container_path = "/opt/data"
          efs            = true
          efs_posix_user = {
            uid = local.hermes_uid
            gid = local.hermes_gid
          }
        }
      }
    }

    /*
    Main container. "user" is intentionally left unset: the upstream
    entrypoint (s6-overlay) starts as root to drop privileges to "hermes"
    itself, so forcing a non-root user here would break that startup
    sequence (Security Hub ECS.20 is not met for this container as a result
    -- see the README's Security section). For the same reason,
    read_only_root_filesystem is left unset: s6-overlay needs to write to
    its own runtime directories outside /opt/data.
    */
    main = {
      image      = local.hermes_image
      command    = ["gateway", "run"]
      depends_on = { init = "SUCCESS" }
      port_mappings = {
        gateway = {
          container_port    = local.hermes_gateway_port
          target_group_arns = [aws_lb_target_group.alb_hermes_gateway.arn]
        }
        dashboard = {
          container_port    = local.hermes_dashboard_port
          target_group_arns = [aws_lb_target_group.alb_hermes_dashboard.arn]
        }
      }
      environment = {
        HERMES_DASHBOARD                     = "1"
        HERMES_DASHBOARD_HOST                = "0.0.0.0"
        HERMES_DASHBOARD_PORT                = tostring(local.hermes_dashboard_port)
        HERMES_DASHBOARD_BASIC_AUTH_USERNAME = local.hermes_dashboard_username
        API_SERVER_ENABLED                   = "true"    # Turns on the OpenAI-compatible API server (off by default)
        API_SERVER_HOST                      = "0.0.0.0" # Binds beyond loopback so the ALB can reach it
      }
      secrets = {
        HERMES_DASHBOARD_BASIC_AUTH_PASSWORD = random_password.hermes_dashboard_password.result
        HERMES_DASHBOARD_BASIC_AUTH_SECRET   = random_password.hermes_dashboard_secret.result
        API_SERVER_KEY                       = random_password.hermes_api_server_key.result
      }
      mount_points = {
        data = {
          container_path = "/opt/data"
          efs            = true
          efs_posix_user = {
            uid = local.hermes_uid
            gid = local.hermes_gid
          }
        }
      }
    }
  }

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
  }
  security_group_connect_ingress = {
    "alb_gateway" = {
      from_port                    = local.hermes_gateway_port
      referenced_security_group_id = aws_security_group.alb.id
    }
    "alb_dashboard" = {
      from_port                    = local.hermes_dashboard_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
}

/*
----------------------------------------------------------------------------
Outputs
----------------------------------------------------------------------------
*/

output "hermes_dashboard_username" {
  description = "Hermes dashboard HTTP Basic Auth username"
  value       = local.hermes_dashboard_username
}

output "hermes_dashboard_password" {
  description = "Hermes dashboard HTTP Basic Auth password"
  value       = random_password.hermes_dashboard_password.result
  sensitive   = true
}

output "hermes_gateway_api_key" {
  description = "Bearer token for the Hermes gateway's OpenAI-compatible API (port 8642)"
  value       = random_password.hermes_api_server_key.result
  sensitive   = true
}
