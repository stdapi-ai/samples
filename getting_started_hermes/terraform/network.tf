/*
============================================================================
VPC Configuration
============================================================================
Creates the VPC, subnets, and ingress defaults for the deployment.
*/

/*
----------------------------------------------------------------------------
VPC Module
----------------------------------------------------------------------------
*/

module "vpc" {
  source  = "JGoutin/vpc/aws"
  version = "~> 1.0"

  name_prefix             = module.stdapi_ai.name_prefix
  internet_access_allowed = true
  public_subnets_enabled  = true
  public_to_app_ports = {
    "gateway" = {
      from_port = local.hermes_gateway_port
      to_port   = local.hermes_gateway_port
      protocol  = "tcp"
    }
    "dashboard" = {
      from_port = local.hermes_dashboard_port
      to_port   = local.hermes_dashboard_port
      protocol  = "tcp"
    }
  }
  public_ingress_ports = {
    "hermes-gateway" = {
      from_port = local.hermes_gateway_port
    }
    "hermes-dashboard" = {
      from_port = local.hermes_dashboard_port
    }
  }
}
