terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state: create this bucket + lock table once (see docs/runbook.md "Bootstrap").
  # Pass the rest with: terraform init -backend-config=envs/<env>.backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "expense-tracker"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "expense-tracker-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
