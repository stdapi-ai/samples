/*
============================================================================
OpenClaw Deployment
============================================================================
Deploys OpenClaw (https://github.com/openclaw/openclaw) using ECS Fargate,
preconfigured to use stdapi.ai/Amazon Bedrock as its model backend.

The image is referenced directly from GitHub Container Registry
(ghcr.io/openclaw/openclaw) and pulled by Fargate with no credential.

Agent sandboxing (agents.defaults.sandbox.mode other than "off") requires
mounting the host Docker socket to run tool calls in a nested container,
which Fargate does not expose. Sandboxing is therefore off in the seeded
config below: tool calls run directly inside this task, and this task's
own container boundary (no host socket, no elevated capabilities) is the
only isolation an agent's tool calls run under.
*/

locals {
  #: Pinned OpenClaw image tag; verified to resolve and pull anonymously from ghcr.io.
  openclaw_image_tag = "2026.7.1-slim"
  openclaw_image     = "ghcr.io/openclaw/openclaw:${local.openclaw_image_tag}"

  #: Gateway + Control UI port; both are multiplexed on this single port.
  openclaw_port = 18789

  # The published image is built on node:24-bookworm(-slim), whose built-in
  # "node" user is uid 1000 / gid 1000; EFS/S3 Files POSIX users must match
  # it so the non-root runtime user can read/write its own state.
  openclaw_uid = 1000
  openclaw_gid = 1000

  openclaw_home        = "/home/node/.openclaw"
  openclaw_auth_config = "/home/node/.config/openclaw"

  # Provider id OpenClaw's config registers stdapi.ai under, and the Bedrock
  # model routed through it. Change the model to any Bedrock model ID your
  # account has access to (see the README's Customization section).
  openclaw_provider_id = "stdapi"
  openclaw_model       = "anthropic.claude-fable-5"
}

/*
----------------------------------------------------------------------------
Gateway Token
----------------------------------------------------------------------------
Delivered to the container via 'secrets' (SSM-backed), never 'environment'
(Security Hub ECS.8).
*/

resource "random_password" "openclaw_gateway_token" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "openclaw" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-openclaw"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  enable_execute_command            = true # Required for "aws ecs execute-command" (Control UI device pairing)
  health_check_grace_period_seconds = 60

  # OpenClaw keeps per-agent state (SQLite DBs, session transcripts) on EFS
  # under a single gateway process; running more than one task would let two
  # gateways write that same state concurrently. Pin to exactly one task.
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 1

  container_definitions = {
    /*
    Init container: seeds openclaw.json from the read-only S3 Files mount on
    first boot only, so user edits made after deployment (models, allowed
    origins, additional providers, ...) survive every redeploy. Reuses the
    OpenClaw image itself (already needed, has "sh"/"cp") rather than
    pulling a second image.
    */
    init = {
      image                     = local.openclaw_image
      essential                 = false
      user                      = "${local.openclaw_uid}:${local.openclaw_gid}"
      entrypoint                = ["sh", "-c"]
      command                   = ["if [ ! -f ${local.openclaw_home}/openclaw.json ]; then cp /mnt/seed/openclaw.json ${local.openclaw_home}/openclaw.json; fi"]
      read_only_root_filesystem = true
      mount_points = {
        seed = {
          container_path = "/mnt/seed"
          read_only      = true
          s3_files       = true
          s3_files_posix_user = {
            uid = local.openclaw_uid
            gid = local.openclaw_gid
          }
          s3_files_files = {
            "openclaw.json" = templatefile("${path.module}/openclaw/openclaw.json.tftpl", {
              allowed_origin = local.openclaw_control_ui_url
              base_url       = local.stdapi_openai_api_url
              provider_id    = local.openclaw_provider_id
              model_id       = local.openclaw_model
            })
          }
        }
        openclaw_home = {
          container_path = local.openclaw_home
          efs            = true
          efs_posix_user = {
            uid = local.openclaw_uid
            gid = local.openclaw_gid
          }
        }
      }
    }

    /*
    Main container. "read_only_root_filesystem" is intentionally left unset:
    OpenClaw's own plugin/runtime writes outside its EFS-mounted state
    directories (npm/node caches, /tmp) could not be verified against the
    image, so this sample does not risk breaking startup by guessing
    (Security Hub ECS.5 is not met for this container as a result -- see the
    README's Security section).
    */
    main = {
      image      = local.openclaw_image
      user       = "${local.openclaw_uid}:${local.openclaw_gid}"
      depends_on = { init = "SUCCESS" }
      port_mappings = {
        gateway = {
          container_port    = local.openclaw_port
          target_group_arns = [aws_lb_target_group.alb_openclaw.arn]
        }
      }
      health_check = {
        # Ref: https://docs.openclaw.ai/gateway/health -- GET /health returns
        # {"ok":true,"status":"live"} with no auth and no session created.
        command      = ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:${local.openclaw_port}/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""]
        start_period = 30
        interval     = 30
        retries      = 3
      }
      secrets = {
        OPENCLAW_GATEWAY_TOKEN = random_password.openclaw_gateway_token.result
        STDAPI_API_KEY         = module.stdapi_ai.api_key
      }
      mount_points = {
        openclaw_home = {
          container_path = local.openclaw_home
          efs            = true
          efs_posix_user = {
            uid = local.openclaw_uid
            gid = local.openclaw_gid
          }
        }
        openclaw_auth_config = {
          container_path = local.openclaw_auth_config
          efs            = true
          efs_posix_user = {
            uid = local.openclaw_uid
            gid = local.openclaw_gid
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
    "alb" = {
      from_port                    = local.openclaw_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
}

/*
----------------------------------------------------------------------------
Outputs
----------------------------------------------------------------------------
*/

output "openclaw_gateway_token" {
  description = "OpenClaw gateway auth token (needed for 'devices approve --token' pairing from outside the container)"
  value       = random_password.openclaw_gateway_token.result
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name (for 'aws ecs execute-command' device pairing, see the README)"
  value       = module.openclaw.ecs_cluster_name
}
