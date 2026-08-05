/*
============================================================================
n8n Deployment
============================================================================
Deploys n8n using ECS Fargate with stdapi.ai as the OpenAI-compatible and
Anthropic-compatible backend, preconfigured with a credential pointed at
stdapi.ai and a set of runnable sample workflows.
*/

variable "n8n_owner_email" {
  type        = string
  default     = "owner@example.com"
  description = "Email address for the n8n instance owner account, pre-provisioned non-interactively (see N8N_INSTANCE_OWNER_MANAGED_BY_ENV below). Change this before applying if you want a real address."
}

locals {
  n8n_port      = 5678
  n8n_image_tag = "2.34.1"
  # The official image, referenced directly: nothing is built or pushed
  # locally, and Fargate pulls it from Docker Hub with no credential.
  n8n_image = "docker.io/n8nio/n8n:${local.n8n_image_tag}"

  # n8n restricts Read/Write File nodes to this directory by default; mounting
  # the persistent EFS volume there means the sample workflows need no extra
  # configuration to read or write files.
  n8n_files_dir = "/home/node/.n8n-files"

  n8n_seed_dir = "${path.module}/n8n_seed"

  # Every file the "import" container needs, materialized on a read-only S3
  # Files volume before either container starts. Only the two templated
  # files carry a runtime value (the gateway URL and API key); the rest are
  # copied verbatim from the committed sample workflows.
  n8n_seed_files = merge(
    {
      "credentials.json" = templatefile("${local.n8n_seed_dir}/credentials.json.tftpl", {
        api_key       = module.stdapi_ai.api_key
        openai_url    = local.stdapi_openai_api_url
        anthropic_url = local.stdapi_anthropic_api_url
      })
      "workflows/completions.json" = templatefile("${local.n8n_seed_dir}/workflows/completions.json.tftpl", {
        openai_url = local.stdapi_openai_api_url
      })
    },
    {
      for f in fileset("${local.n8n_seed_dir}/workflows", "*.json") :
      "workflows/${f}" => file("${local.n8n_seed_dir}/workflows/${f}")
    }
  )

  n8n_db_environment = {
    DB_TYPE                = "postgresdb"
    DB_POSTGRESDB_HOST     = local.postgres_address
    DB_POSTGRESDB_PORT     = tostring(local.postgres_port)
    DB_POSTGRESDB_DATABASE = local.postgres_n8n_database
    DB_POSTGRESDB_USER     = local.postgres_n8n_username

    # Encrypt the connection without verifying Aurora's certificate chain:
    # verifying it would mean shipping the RDS CA bundle and keeping it
    # current, for a hop that never leaves the VPC and is already restricted
    # to this security group. Set DB_POSTGRESDB_SSL_CA to the bundle to
    # verify it instead.
    DB_POSTGRESDB_SSL_ENABLED             = "true"
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED = "false"
  }

  # Offline-friendly switches: no telemetry, no external template gallery
  # calls, no personalization survey to click through after the owner
  # account is pre-provisioned below.
  n8n_offline_environment = {
    N8N_DIAGNOSTICS_ENABLED           = "false"
    N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
    N8N_TEMPLATES_ENABLED             = "false"
    N8N_PERSONALIZATION_ENABLED       = "false"
  }
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
Two containers: "import" seeds the stdapi.ai credential and the sample
workflows into Postgres and exits; "main" is the n8n server, and only starts
once "import" has exited successfully (depends_on / condition SUCCESS).
*/

module "n8n" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-n8n"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS

  cpu    = 1
  memory = 2048

  container_definitions = {
    import = {
      image      = local.n8n_image
      essential  = false
      user       = "node"
      entrypoint = ["/bin/sh", "-c"]
      command = [
        "n8n import:credentials --input=/seed/credentials.json && n8n import:workflow --separate --input=/seed/workflows"
      ]
      environment = merge(local.n8n_db_environment, local.n8n_offline_environment)
      secrets = {
        N8N_ENCRYPTION_KEY     = random_password.n8n_encryption_key.result
        DB_POSTGRESDB_PASSWORD = local.postgres_n8n_password
      }
      mount_points = {
        seed = {
          container_path = "/seed"
          read_only      = true # Only ever read by "import"; never written back to.
          s3_files       = true
          s3_files_files = local.n8n_seed_files
          s3_files_posix_user = {
            uid = 1000 # "node", the image's built-in non-root user; both containers run as it.
            gid = 1000
          }
        }
      }
    }
    main = {
      image = local.n8n_image
      user  = "node"
      port_mappings = {
        http = {
          container_port    = local.n8n_port
          target_group_arns = [aws_lb_target_group.alb_n8n.arn]
        }
      }
      health_check = {
        # No curl/wget guaranteed in the image; Node itself always is.
        command      = ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:${local.n8n_port}/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""]
        start_period = 60
        interval     = 30
        retries      = 3
      }
      environment = merge(local.n8n_db_environment, local.n8n_offline_environment, {
        N8N_HOST        = var.alb_domain_name
        N8N_PROTOCOL    = "https"
        N8N_WEBHOOK_URL = "${local.n8n_url}/"
        N8N_PROXY_HOPS  = "1" # Behind the ALB: trust one hop of X-Forwarded-*

        # Pre-provisions the instance owner on every start, so there is no
        # interactive first-run signup. n8n overwrites this account and
        # rejects API/UI changes to it while this is enabled.
        N8N_INSTANCE_OWNER_MANAGED_BY_ENV = "true"
        N8N_INSTANCE_OWNER_EMAIL          = var.n8n_owner_email
        N8N_INSTANCE_OWNER_FIRST_NAME     = "stdapi.ai"
        N8N_INSTANCE_OWNER_LAST_NAME      = "Sample"
      })
      secrets = {
        N8N_ENCRYPTION_KEY               = random_password.n8n_encryption_key.result
        DB_POSTGRESDB_PASSWORD           = local.postgres_n8n_password
        N8N_INSTANCE_OWNER_PASSWORD_HASH = local.n8n_owner_password_hash
      }
      mount_points = {
        seed = {
          container_path = "/seed"
          read_only      = true # Only ever read by "import"; never written back to.
          s3_files       = true
          s3_files_files = local.n8n_seed_files
          s3_files_posix_user = {
            uid = 1000 # "node", the image's built-in non-root user; both containers run as it.
            gid = 1000
          }
        }
        files = {
          container_path = local.n8n_files_dir
          efs            = true
          efs_posix_user = {
            uid = 1000 # "node", the image's built-in non-root user
            gid = 1000
          }
        }
      }
      depends_on = {
        import = "success"
      }
    }
  }

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "n8n"

  security_group_connect_egress = {
    "stdapiai" = {
      from_port                    = module.stdapi_ai.port
      referenced_security_group_id = module.stdapi_ai.security_group_id
    }
    "postgresql" = {
      from_port                    = local.postgres_port
      referenced_security_group_id = aws_security_group.postgres.id
    }
  }
  security_group_connect_ingress = {
    "alb" = {
      from_port                    = local.n8n_port
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

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

# n8n needs a bcrypt hash, not the plaintext password, in
# N8N_INSTANCE_OWNER_PASSWORD_HASH; OpenTofu's built-in bcrypt() function
# computes it, so no local tool (htpasswd, openssl, ...) is required.
resource "random_password" "n8n_owner_password" {
  length  = 24
  special = false
}

# bcrypt() salts randomly, so it returns a different hash on every run. Holding
# it in a terraform_data that ignores changes to its input keeps the hash
# computed at creation time, instead of churning the task definition every apply.
resource "terraform_data" "n8n_owner_password_hash" {
  input = bcrypt(random_password.n8n_owner_password.result)
  lifecycle {
    ignore_changes = [input]
  }
}

locals {
  n8n_owner_password_hash = terraform_data.n8n_owner_password_hash.output
}

output "n8n_owner_email" {
  description = "Email to sign in to n8n with"
  value       = var.n8n_owner_email
}

output "n8n_owner_password" {
  description = "Password to sign in to n8n with"
  value       = random_password.n8n_owner_password.result
  sensitive   = true
}
