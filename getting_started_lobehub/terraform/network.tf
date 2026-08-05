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
  # Free gateway endpoint keeping LobeHub's server-side S3 traffic off the NAT.
  vpc_endpoints_services = ["s3"]
  public_to_app_ports = {
    "http" = {
      from_port = local.lobehub_port
      to_port   = local.lobehub_port
      protocol  = "tcp"
    }
  }
  public_ingress_ports = {
    "lobehub" = {
      from_port = local.alb_listener_port
    }
  }
}
