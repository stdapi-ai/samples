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
    "http" = {
      from_port = local.docling_port
      to_port   = local.docling_port
      protocol  = "tcp"
    }
  }
  public_ingress_ports = {
    "docling" = {
      from_port = local.alb_listener_port
    }
  }
}
