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
      version = ">= 6.27.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }

  provider_meta "aws" {
    user_agent = ["APN_1.1/pc_72gxmztpjz2hm5qnkkg0iiazo$"]
  }
}

provider "aws" {
  default_tags {
    tags = {
      aws-apn-id = "pc:72gxmztpjz2hm5qnkkg0iiazo"
    }
  }
}
