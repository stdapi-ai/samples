/*
============================================================================
Providers and Requirements
============================================================================
Defines required providers and shared provider configuration.
*/

/*
----------------------------------------------------------------------------
Required Providers
----------------------------------------------------------------------------
*/

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

/*
----------------------------------------------------------------------------
Inputs
----------------------------------------------------------------------------
*/

variable "docker_host" {
  type        = string
  default     = null
  description = "Optional Docker/Podman socket for the Docker provider"
}

/*
----------------------------------------------------------------------------
Docker Provider Configuration
----------------------------------------------------------------------------
Authenticates with ECR for pushing container images
*/

provider "docker" {
  host = var.docker_host
  registry_auth {
    address  = data.aws_ecr_authorization_token.token.proxy_endpoint
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}

/*
----------------------------------------------------------------------------
Data Sources
----------------------------------------------------------------------------
*/

data "aws_ecr_authorization_token" "token" {}
