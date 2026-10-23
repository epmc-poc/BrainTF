# The mocked providers need their registry source (github and gitlab are not under hashicorp/).
# Terraform 1.14+: older versions fail on these tests (see docs/terraform_testing.md).
terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    github = {
      source = "integrations/github"
    }
    gitlab = {
      source = "gitlabhq/gitlab"
    }
  }
}
