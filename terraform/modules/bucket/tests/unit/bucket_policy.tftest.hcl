# Bucket policy JSON, rendered by the real AWS provider with fake credentials. No AWS access.

variables {
  test_aws_region = "eu-west-1"

  bucket_name = "artifacts-braintf-eu-west-1"
  account_id  = "123456789012"
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

provider "aws" {
  region                      = var.test_aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# The data sources of the upstream S3 module that would call AWS.
override_data {
  target = module.s3_bucket.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:user/terraform-test"
    id         = "123456789012"
  }
}

override_data {
  target = module.s3_bucket.data.aws_canonical_user_id.this
  values = {
    id = "0000000000000000000000000000000000000000000000000000000000000000"
  }
}

run "policy_denies_insecure_transport" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[0].Sid == "denyInsecureTransport"
    error_message = "The first statement must be the TLS-only rule."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[0].Effect == "Deny"
    error_message = "The TLS-only rule must be a Deny."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The Deny must apply to requests without TLS."
  }

  assert {
    condition = toset(jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[0].Resource) == toset([
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/*",
    ])
    error_message = "The TLS-only rule must cover the bucket and every object in it."
  }
}

run "policy_grants_only_this_account" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[1].Principal.AWS == "arn:aws:iam::${var.account_id}:root"
    error_message = "The Allow statement must be limited to the account root principal."
  }

  assert {
    condition     = !contains(flatten([jsondecode(data.aws_iam_policy_document.s3_bucket_policy.json).Statement[1].Action]), "s3:*")
    error_message = "The Allow statement must list actions explicitly, not s3:*."
  }
}
