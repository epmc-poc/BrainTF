terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project     = var.vcs_repo_name
      InstanceId  = var.instance_id
      Environment = var.environment
      Team        = var.team
      DeployedBy  = var.deployed_by
      OwnerEmail  = var.owner_mail
    }
  }
}
