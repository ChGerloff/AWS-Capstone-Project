terraform {
  cloud {
    organization = "neuefische_capstone_ger"

    workspaces {
      name = "capstonetest"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
