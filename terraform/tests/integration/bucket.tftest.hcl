# Integration test for terraform/modules/bucket: creates a real bucket in the test account, reads it back from S3,
# then terraform test destroys it. Needs the role and KMS key from account_setup.

provider "aws" {
  default_tags {
    tags = {
      ManagedBy = "terraform-test"
      Purpose   = "braintf-integration-test"
    }
  }
}

# Same placeholders and rule as main_module, but with the valid prefix "artifacts/" (see finding 3).
variables {
  test_directories = ["logs/", "artifacts/"]
  test_lifecycle_rules = [
    {
      id                                 = "artifacts-retention"
      enabled                            = true
      prefix                             = "artifacts/"
      expiration_days                    = 3
      noncurrent_version_expiration_days = 1
    },
  ]
}

run "setup" {
  module {
    source = "./bucket_setup"
  }
}

run "create_bucket" {
  module {
    source = "../../modules/bucket"
  }

  variables {
    bucket_name        = run.setup.bucket_name
    account_id         = run.setup.account_id
    kms_key_arn        = run.setup.kms_key_arn
    force_destroy      = true
    create_directories = true
    directories        = var.test_directories
    lifecycle_rules    = var.test_lifecycle_rules
  }

  assert {
    condition     = output.artifacts_bucket_name == run.setup.bucket_name
    error_message = "The module must create the bucket under the requested name."
  }

  assert {
    condition     = output.artifacts_bucket_arn == "arn:aws:s3:::${run.setup.bucket_name}"
    error_message = "Unexpected bucket ARN: ${output.artifacts_bucket_arn}"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule[0].status == "Enabled"
    error_message = "AWS must accept the lifecycle rule."
  }
}

run "tls_only_policy_is_attached_in_aws" {
  module {
    source = "./bucket_verify"
  }

  variables {
    bucket_name = run.setup.bucket_name
    object_keys = var.test_directories
  }

  assert {
    condition     = jsondecode(output.policy).Statement[0].Sid == "denyInsecureTransport"
    error_message = "The TLS-only bucket policy must be attached in AWS: ${output.policy}"
  }
}

# Open findings: these runs fail until the code is fixed. Keep them last.

# The placeholders are written before the bucket's KMS encryption and versioning apply (a race).
run "finding_placeholder_objects_use_bucket_kms_key_and_versioning" {
  module {
    source = "./bucket_verify"
  }

  variables {
    bucket_name = run.setup.bucket_name
    object_keys = var.test_directories
  }

  assert {
    condition     = alltrue([for o in values(output.objects) : o.server_side_encryption == "aws:kms" && o.sse_kms_key_id == run.setup.kms_key_arn])
    error_message = "Placeholder objects must be encrypted with the bucket's KMS key: ${jsonencode(output.objects)}"
  }

  assert {
    condition     = alltrue([for o in values(output.objects) : o.version_id != "" && o.version_id != "null"])
    error_message = "Placeholder objects must be stored after versioning is enabled: ${jsonencode(output.objects)}"
  }
}
