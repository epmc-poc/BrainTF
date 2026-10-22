# Unit tests for the lifecycle rules of terraform/modules/bucket. No AWS access.

mock_provider "aws" {
  source = "../mocks/aws"
}

variables {
  bucket_name = "artifacts-braintf-eu-west-1"
  account_id  = "123456789012"
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"

  default_abort_days = 7
}

run "lifecycle_rule_is_rendered" {
  module {
    source = "../../modules/bucket"
  }

  command = plan

  variables {
    lifecycle_rules = [
      {
        id                                 = "artifacts-retention"
        enabled                            = true
        prefix                             = "artifacts/"
        expiration_days                    = 3
        noncurrent_version_expiration_days = 1
      },
      {
        id      = "paused"
        enabled = false
      },
    ]
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule : r.status] == ["Enabled", "Disabled"]
    error_message = "enabled = true/false must map to status Enabled/Disabled."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[0].filter[0].prefix == var.lifecycle_rules[0].prefix
    error_message = "The rule prefix must be passed through."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[0].expiration[0].days == var.lifecycle_rules[0].expiration_days
    error_message = "expiration_days must become expiration.days."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == var.lifecycle_rules[0].noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must become noncurrent_version_expiration.noncurrent_days."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[1].expiration) == 0 && length(aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[1].noncurrent_version_expiration) == 0
    error_message = "A rule without expiration settings must not get expiration blocks."
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule : r.abort_incomplete_multipart_upload[0].days_after_initiation == var.default_abort_days])
    error_message = "Incomplete multipart uploads must be aborted after ${var.default_abort_days} days by default."
  }
}

run "rejects_abort_days_above_seven" {
  module {
    source = "../../modules/bucket"
  }

  command = plan

  variables {
    lifecycle_rules = [
      {
        id                                     = "too-long"
        enabled                                = true
        abort_incomplete_multipart_upload_days = 30
      },
    ]
  }

  expect_failures = [var.lifecycle_rules]
}

# Open findings: these runs fail until the code is fixed. Keep them last.

# S3 lifecycle prefixes are literal: "artifacts/*", which main_module passes, matches nothing under artifacts/.
run "finding_wildcard_lifecycle_prefix_is_rejected" {
  module {
    source = "../../modules/bucket"
  }

  command = plan

  variables {
    lifecycle_rules = [
      {
        id              = "artifacts-retention"
        enabled         = true
        prefix          = "artifacts/*"
        expiration_days = 3
      },
    ]
  }

  expect_failures = [var.lifecycle_rules]
}
