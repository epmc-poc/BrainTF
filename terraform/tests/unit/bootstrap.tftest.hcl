# Unit tests for terraform/bootstrap. No AWS access; the mocked local provider writes no files.

mock_provider "aws" {
  source = "../mocks/aws"
}

mock_provider "local" {
  mock_data "local_file" {
    defaults = {
      content = "vcs_repo_name = \"BrainTF\"\n"
    }
  }
}

# The upstream KMS and S3 modules are black boxes here.
override_module {
  target = module.s3_bucket_kms_key
  outputs = {
    key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }
}

override_module {
  target = module.s3_state_bucket
  outputs = {
    s3_bucket_id  = "terraform-test-state-bucket"
    s3_bucket_arn = "arn:aws:s3:::terraform-test-state-bucket"
  }
}

variables {
  vcs_repo_name = "BrainTF"
  environment   = "test"
  team          = "test"
  deployed_by   = "terraform-test"
  owner_mail    = "test@example.com"

  main_module_dir       = "../main_module"
  main_module_state_key = "main-module/terraform.tfstate"
}

run "state_bucket_name_is_lowercase_and_regional" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  assert {
    condition     = local.state_bucket == "${var.platform_state_bucket_prefix}-${lower(var.vcs_repo_name)}-${data.aws_region.current.region}"
    error_message = "State bucket must be <prefix>-<repo in lowercase>-<region>, got ${local.state_bucket}"
  }
}

run "state_bucket_name_replaces_underscores_and_uses_custom_prefix" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  variables {
    vcs_repo_name                = "Brain_TF"
    platform_state_bucket_prefix = "tfstate"
  }

  assert {
    condition     = local.state_bucket == "${var.platform_state_bucket_prefix}-${replace(lower(var.vcs_repo_name), "_", "-")}-${data.aws_region.current.region}"
    error_message = "Underscores must become dashes and the custom prefix must be used, got ${local.state_bucket}"
  }
}

run "backend_file_is_generated_for_main_module" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "backend.generated.tf must be generated while main_module has no backend block of its own."
  }

  assert {
    condition     = local_file.backend_config[0].filename == "${path.module}/${var.main_module_dir}/backend.generated.tf"
    error_message = "The backend file must be written next to main_module's configuration, got ${local_file.backend_config[0].filename}"
  }

  assert {
    condition = alltrue([
      strcontains(local_file.backend_config[0].content, "bucket       = \"${local.state_bucket}\""),
      strcontains(local_file.backend_config[0].content, "key          = \"${var.main_module_state_key}\""),
      strcontains(local_file.backend_config[0].content, "region       = \"${data.aws_region.current.region}\""),
      strcontains(local_file.backend_config[0].content, "encrypt      = true"),
      strcontains(local_file.backend_config[0].content, "use_lockfile = true"),
    ])
    error_message = "The generated S3 backend must use the state bucket, the main-module key, the current region, encryption and S3 locking."
  }
}

run "tfvars_are_copied_to_main_module" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  assert {
    condition     = local_file.this.filename == "${path.module}/${var.main_module_dir}/terraform.auto.tfvars"
    error_message = "bootstrap must copy its tfvars into main_module/terraform.auto.tfvars, got ${local_file.this.filename}"
  }

  assert {
    condition     = local_file.this.content == data.local_file.this.content
    error_message = "The copied tfvars must match terraform.tfvars byte for byte."
  }
}

# apply: the policy needs the bucket ARN, which only exists after apply (mocked, nothing is created).
run "state_bucket_denies_insecure_transport" {
  module {
    source = "../../bootstrap"
  }

  command = apply

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state_bucket_policy.policy).Statement[0].Effect == "Deny"
    error_message = "The first statement of the state bucket policy must be a Deny."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state_bucket_policy.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The state bucket must deny requests that are not sent over TLS."
  }

  assert {
    condition = toset(jsondecode(aws_s3_bucket_policy.state_bucket_policy.policy).Statement[0].Resource) == toset([
      module.s3_state_bucket.s3_bucket_arn,
      "${module.s3_state_bucket.s3_bucket_arn}/*",
    ])
    error_message = "The TLS-only rule must cover the bucket and every object in it."
  }
}

# Open findings: these runs fail until the code is fixed. Keep them last.

# replace() without slashes is not a regex, so "+" stays in the bucket name.
run "finding_state_bucket_name_keeps_only_s3_characters" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  variables {
    vcs_repo_name = "Brain+TF"
  }

  assert {
    condition     = can(regex("^[a-z0-9.-]+$", local.state_bucket))
    error_message = "The state bucket name must contain only a-z, 0-9, '.' and '-', got ${local.state_bucket}"
  }
}

# vcs_repo_name has no validation; 36 characters overflow the 63-character bucket name limit.
run "finding_repo_name_too_long_for_bucket_is_rejected" {
  module {
    source = "../../bootstrap"
  }

  command = plan

  variables {
    vcs_repo_name = "braintf-repository-name-is-too-long1"
  }

  expect_failures = [var.vcs_repo_name]
}
