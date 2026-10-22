terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project   = var.project_tag
      ManagedBy = "Terraform"
      Purpose   = "terraform-integration-tests"
    }
  }
}

provider "github" {
  token = var.vcs_token
  owner = local.repo_owner
}
