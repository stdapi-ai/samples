terraform {
  required_providers {
    aws  = { source = "hashicorp/aws", version = ">= 6.27.0" }
    http = { source = "hashicorp/http", version = ">= 3.0" }
  }

  provider_meta "aws" {
    user_agent = ["APN_1.1/pc_72gxmztpjz2hm5qnkkg0iiazo$"]
  }
}

# Main provider for primary deployment region (Paris)
provider "aws" {
  region = "eu-west-3"
  default_tags {
    tags = {
      aws-apn-id = "pc:72gxmztpjz2hm5qnkkg0iiazo"
    }
  }
}
