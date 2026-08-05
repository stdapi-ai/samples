/*
============================================================================
Home Assistant + wyoming-openai Deployment
============================================================================
Deploys Home Assistant and wyoming-openai as two containers in a single ECS
Fargate task, so Home Assistant reaches wyoming-openai over localhost --
simpler than service discovery, and the point of running them in one task.

wyoming-openai bridges Home Assistant's Assist voice pipeline (which speaks
the Wyoming protocol) to stdapi.ai's OpenAI-compatible audio routes, using
Amazon Transcribe for speech-to-text and Amazon Polly for text-to-speech.

This is a demonstration sample, not a production Home Assistant deployment:
Fargate has no access to a home network, so Zigbee/Z-Wave USB dongles, mDNS
device discovery, and LAN voice satellites do not work here. A voice
satellite on your home LAN cannot reach this deployment without a VPN.
*/

locals {
  home_assistant_port      = 8123
  home_assistant_image_tag = "2026.7.4" # Last release configuring the HTTP integration through configuration.yaml -- see the README for why 2026.8+ isn't used here.
  home_assistant_image     = "ghcr.io/home-assistant/home-assistant:${local.home_assistant_image_tag}"

  wyoming_port             = 10300
  wyoming_openai_image_tag = "0.5.0"
  wyoming_openai_image     = "ghcr.io/roryeckel/wyoming_openai:${local.wyoming_openai_image_tag}"

  # Home Assistant's own subnets aren't the source the ALB connects from --
  # the ALB's ENIs live in the public subnets it's deployed into (alb.tf), so
  # that's the CIDR range Home Assistant must trust as a reverse proxy.
  configuration_yaml = templatefile("${path.module}/config/configuration.yaml.tpl", {
    trusted_proxy_cidrs = module.vpc.public_subnets_cidr_blocks
  })
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "home_assistant" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  # Kept short: some resource names the module derives from this (e.g. the
  # backup vault, the S3 Files IAM role) exceed AWS name-length limits with
  # the full "-home-assistant" suffix -- see alb.tf's target group name for
  # the same constraint.
  name_prefix        = "${local.name_prefix}-ha"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  # Home Assistant keeps its state (recorder database, .storage, this
  # config) on a single EFS volume; a second task writing to it concurrently
  # would corrupt it. The module defaults to one task per subnet with
  # autoscaling on top of that, so both bounds are pinned to 1 here.
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 1

  enable_execute_command = true

  container_definitions = {
    /*
    Seeds configuration.yaml into the EFS /config volume on first boot only,
    from a read-only S3 Files mount point holding the seed file (uploaded
    before the task definition is even registered, so the seed is always
    there by the time this container runs). Runs before "home-assistant"
    (essential = false + a SUCCESS dependency), and never overwrites a
    configuration.yaml a user has already edited -- redeploying this stack
    does not touch it once it exists.
    */
    init = {
      image      = local.home_assistant_image # Reused so the init step has a shell without pulling a third image.
      essential  = false
      entrypoint = ["/bin/sh"]
      command    = ["-c", "[ -f /config/configuration.yaml ] || cp /config-seed/configuration.yaml /config/configuration.yaml"]
      mount_points = {
        config = {
          container_path = "/config"
          efs            = true
          efs_posix_user = { uid = 0, gid = 0 } # Home Assistant's image declares no USER and runs as root; see the README.
        }
        config_seed = {
          container_path = "/config-seed"
          read_only      = true
          s3_files       = true
          s3_files_files = {
            "configuration.yaml" = local.configuration_yaml
          }
        }
      }
    }

    home-assistant = {
      image      = local.home_assistant_image
      depends_on = { init = "SUCCESS" }
      port_mappings = {
        http = {
          container_port    = local.home_assistant_port
          target_group_arns = [aws_lb_target_group.alb_home_assistant.arn]
        }
      }
      health_check = {
        # A TCP probe rather than an HTTP one: the image's toolset (curl,
        # wget) isn't guaranteed by upstream, but Home Assistant is Python,
        # so this only assumes a Python interpreter. The ALB's own HTTP
        # health check on "/" is what actually gates traffic.
        command      = ["CMD-SHELL", "python3 -c \"import socket; socket.create_connection(('127.0.0.1', ${local.home_assistant_port}), 5)\" || exit 1"]
        start_period = 60
        interval     = 30
        retries      = 3
      }
      mount_points = {
        config = {
          container_path = "/config"
          efs            = true
          efs_posix_user = { uid = 0, gid = 0 }
        }
      }
    }

    wyoming-openai = {
      image = local.wyoming_openai_image
      user  = "1000:1000" # No USER in the image (defaults to root); safe here since this container holds no state.
      health_check = {
        # Also TCP-only: the Wyoming protocol isn't HTTP, so there's no path
        # to poll -- see the "Known Issues" note in the Home Assistant docs.
        command      = ["CMD-SHELL", "python3 -c \"import socket; socket.create_connection(('127.0.0.1', ${local.wyoming_port}), 5)\" || exit 1"]
        start_period = 30
        interval     = 30
        retries      = 3
      }
      environment = {
        WYOMING_URI          = "tcp://0.0.0.0:${local.wyoming_port}"
        WYOMING_LOG_LEVEL    = "INFO"
        STT_OPENAI_URL       = local.stdapi_openai_api_url
        STT_MODELS           = "amazon.transcribe"
        STT_BACKEND          = "OPENAI"
        TTS_OPENAI_URL       = local.stdapi_openai_api_url
        TTS_MODELS           = "amazon.polly-neural"
        TTS_STREAMING_MODELS = "amazon.polly-neural"
        TTS_VOICES           = "alloy"
        TTS_BACKEND          = "OPENAI"
      }
      secrets = {
        STT_OPENAI_KEY = module.stdapi_ai.api_key
        TTS_OPENAI_KEY = module.stdapi_ai.api_key
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
      from_port                    = local.home_assistant_port
      referenced_security_group_id = aws_security_group.alb.id
    }
  }
}
