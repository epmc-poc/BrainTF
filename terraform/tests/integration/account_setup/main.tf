# Applied once per test AWS account: the CI role for the integration tests, the fixture KMS key and the
# GitHub variables the workflow reads. Needs the account's GitHub OIDC provider (main_module creates it).

data "aws_region" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.oidc_host}"
}

locals {
  oidc_host  = "token.actions.githubusercontent.com"
  repo_owner = split("/", var.vcs_project_path)[0]
  repo_name  = split("/", var.vcs_project_path)[1]

  default_subjects = [
    "repo:${var.vcs_project_path}:pull_request",
    "repo:${var.vcs_project_path}:ref:refs/heads/main",
    "repo:${local.repo_owner}@*/${local.repo_name}@*:pull_request",
    "repo:${local.repo_owner}@*/${local.repo_name}@*:ref:refs/heads/main",
  ]
  subjects = length(var.github_oidc_subjects) > 0 ? var.github_oidc_subjects : local.default_subjects
}

resource "aws_kms_key" "fixture" {
  description             = "Fixture key for the BrainTF Terraform integration tests"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "fixture" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.fixture.key_id
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "${var.name_prefix}-ci"
  description          = "Terraform integration tests from GitHub Actions of ${var.vcs_project_path}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "TestBuckets"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${var.name_prefix}-*", "arn:aws:s3:::${var.name_prefix}-*/*"]
  }

  # The upstream S3 module and the CI leak check list buckets.
  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid       = "UseFixtureKey"
    actions   = ["kms:DescribeKey", "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"]
    resources = [aws_kms_key.fixture.arn]
  }

  # The aws_kms_alias data source; ListAliases has no resource-level permissions.
  statement {
    sid       = "FindFixtureKey"
    actions   = ["kms:ListAliases"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "${var.name_prefix}-ci"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}

resource "github_actions_variable" "role_arn" {
  repository    = local.repo_name
  variable_name = "TF_TEST_ROLE_ARN"
  value         = aws_iam_role.ci.arn
}

resource "github_actions_variable" "region" {
  repository    = local.repo_name
  variable_name = "TF_TEST_AWS_REGION"
  value         = data.aws_region.current.region
}
