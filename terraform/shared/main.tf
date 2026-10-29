# ======================= Account-level shared OIDC providers =======================
# An IAM OIDC provider is unique per issuer URL per AWS account. These providers are
# therefore created ONCE per account by this module and reused by every BrainTF
# instance (the main_module references them via a data source, it does not create them).

# Fetch the issuer TLS thumbprint for each provider.
data "external" "thumbprint" {
  for_each = var.oidc_providers
  program  = ["bash", "${path.module}/get_thumbprint.sh", each.value.url]
}

resource "aws_iam_openid_connect_provider" "this" {
  for_each        = var.oidc_providers
  url             = "https://${each.value.url}"
  client_id_list  = each.value.client_id_list
  thumbprint_list = [data.external.thumbprint[each.key].result.thumbprint]
}

# ======================= Shared Terraform state storage =======================
# One S3 bucket + one KMS key per AWS account holds the Terraform state of ALL
# BrainTF instances. Instance isolation is by key prefix (<instance_id>/...),
# enforced for pipelines by prefix-scoped IAM in modules/oidc.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  state_bucket = "${var.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
}

module "state_kms_key" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=407e3db34a65b384c20ef718f55d9ceacb97a846"

  description              = "KMS key for BrainTF Terraform state encryption (shared per account)"
  enable_key_rotation      = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days  = 7

  key_owners = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]

  computed_aliases = {
    project_alias = {
      name = "braintf-state-key-${data.aws_region.current.region}"
    }
  }

  key_statements = [
    {
      sid = "AllowRootAccountAccess"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
        "kms:ListAliases",
        "kms:ListKeys",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ]
      effect    = "Allow"
      resources = ["*"]
      principals = [
        {
          type        = "AWS"
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
      ]
    }
  ]
}

module "state_bucket" {
  source                  = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=6c5e082b5d2fde77cb59c387a7f553dd2ed5da29"
  create_bucket           = true
  bucket                  = local.state_bucket
  force_destroy           = false
  attach_policy           = false
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = module.state_kms_key.key_arn
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }
}

resource "aws_s3_bucket_policy" "state_bucket_policy" {
  bucket = module.state_bucket.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "DenyInsecureTransport",
        Effect    = "Deny",
        Action    = "s3:*",
        Principal = "*",
        Resource = [
          module.state_bucket.s3_bucket_arn,
          "${module.state_bucket.s3_bucket_arn}/*"
        ],
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
