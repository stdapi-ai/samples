/*
============================================================================
Providers and Requirements
============================================================================
Defines required providers and shared provider configuration.

No Docker provider is required here: every container image (Home Assistant,
wyoming-openai) is referenced directly from ghcr.io and pulled by Fargate
itself, never built or pushed from this machine -- see home_assistant.tf.
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
