/*
============================================================================
SearXNG Search Engine
============================================================================
Deploys SearXNG as a web search backend for Open WebUI
*/

locals {
  searxng_port         = 8080
  searxng_url          = "http://${module.searxng.service_discovery_service_name}.${local.internal_namespace}:${local.searxng_port}/search?q=<query>"
  searxng_source_image = "docker.io/searxng/searxng:${local.searxng_image_tag}"
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "searxng" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-searxng"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  container_definitions = {
    main = {
      image = local.searxng_source_image
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
        # "valkeys" scheme enables TLS to ElastiCache
        SEARXNG_VALKEY_URL = "valkeys://:${random_password.valkey_auth_token.result}@${local.valkey_address}/2"
        SEARXNG_SECRET     = random_password.searxng_secret_key.result
      }
      mount_points = {
        # Ships settings.yml/limiter.toml with no image build. Read-only is safe: the
        # upstream entrypoint only (re)writes /etc/searxng/settings.yml when the file
        # is absent, which never happens here.
        # https://github.com/searxng/searxng/blob/master/container/entrypoint.sh
        #
        # That entrypoint also chowns this directory on start. Objects surfaced through
        # S3 Files do not carry the POSIX ownership the access point enforces on access,
        # so the chown is attempted and logs "Read-only file system" four times per
        # start. It is not fatal, and SearXNG serves normally afterwards.
        config = {
          container_path = "/etc/searxng"
          read_only      = true
          s3_files       = true
          # uid/gid 977 is the "searxng" user baked into the upstream image:
          # https://github.com/searxng/searxng/blob/master/container/dist.dockerfile
          s3_files_posix_user = { uid = 977, gid = 977 }
          s3_files_files = {
            "settings.yml" = file("${path.module}/searxng/settings.yml")
            "limiter.toml" = file("${path.module}/searxng/limiter.toml")
          }
        }
      }
    }
  }

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "searxng"

  security_group_connect_egress = {
    "valkey" = {
      from_port                    = local.valkey_port
      referenced_security_group_id = aws_security_group.valkey.id
    }
  }
}

resource "random_password" "searxng_secret_key" {
  length  = 32
  special = false
}
