/*
============================================================================
Self-hosted ParadeDB PostgreSQL
============================================================================
LobeHub 2.x ("server DB" mode, the only mode it supports since dropping
client-storage/PGlite) needs Postgres with the pg_search extension for its
knowledge-base full-text search. Amazon RDS for PostgreSQL does not support
pg_search: it isn't in RDS's supported-extensions list, ParadeDB's own docs
say managed providers aren't supported until they add it explicitly, and
https://github.com/lobehub/lobehub/issues/12899 documents the same gap on
another managed Postgres (Neon). There is no fallback to a plain-Postgres
search index in LobeHub's migrations, so RDS is not an option today.

This runs the official ParadeDB image (bundles pg_search + pgvector on
Postgres 17) as a single ECS task with its data directory on EFS instead.
*/

locals {
  postgres_port         = 5432
  postgres_database     = "lobechat"
  postgres_data_path    = "/var/lib/postgresql/data"
  postgres_source_image = "docker.io/paradedb/paradedb:${local.postgres_image_tag}"
  postgres_url          = "postgresql://postgres:${random_password.postgres_password.result}@${module.postgres.service_discovery_service_name}.${local.internal_namespace}:${local.postgres_port}/${local.postgres_database}"
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

/*
----------------------------------------------------------------------------
ECS Service
----------------------------------------------------------------------------
*/

module "postgres" {
  source  = "JGoutin/ecs-fargate/aws"
  version = "~> 1.4"

  name_prefix        = "${local.name_prefix}-postgres"
  subnets_ids        = module.vpc.subnets_ids
  security_group_ids = [module.vpc.security_group_id] # Allow Internet HTTPS (image pull, SSM secrets)

  # Pinned to exactly one task: Postgres writes to a single EFS-backed
  # PGDATA directory, so a second concurrent instance would corrupt it.
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 1

  container_definitions = {
    main = {
      # This image's own postgresql.conf sets shared_preload_libraries to
      # "pg_search,pg_cron,pg_stat_statements", which is what makes
      # "CREATE EXTENSION pg_search" (run by LobeHub's startup migration)
      # succeed and is the setting RDS for PostgreSQL cannot be given.
      image = local.postgres_source_image
      # The "postgres" user of the image, matching the EFS access point's
      # enforced POSIX user below. Running as root instead would make the
      # image's entrypoint chown the mount, which the access point forbids.
      # Also required by Security Hub ECS.20.
      user = "999:999"
      port_mappings = {
        postgres = {
          container_port = local.postgres_port
        }
      }
      health_check = {
        command      = ["CMD-SHELL", "pg_isready -U postgres || exit 1"]
        start_period = 30
        interval     = 10
        retries      = 5
      }
      environment = {
        POSTGRES_DB = local.postgres_database
        # A subdirectory of the mount, not its root: PostgreSQL requires a
        # 0700 data directory it owns, and the EFS access point root stays
        # owned by root.
        PGDATA = "${local.postgres_data_path}/pgdata"
      }
      secrets = {
        POSTGRES_PASSWORD = random_password.postgres_password.result
      }
      mount_points = {
        data = {
          container_path = local.postgres_data_path
          efs            = true
          # Matches the "postgres" user (uid/gid 999) baked into the
          # postgres:17-trixie base image ParadeDB builds on.
          efs_posix_user = { uid = 999, gid = 999 }
        }
      }
    }
  }

  service_discovery_dns_namespace_id = local.internal_namespace_id
  service_discovery_dns_name         = "postgres"
}
