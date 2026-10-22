output "bucket_name" {
  description = "Unique bucket name for this test run"
  value       = "${var.name_prefix}-${var.run_id}-${random_id.suffix.hex}"
}

output "account_id" {
  description = "ID of the AWS account the test runs in"
  value       = data.aws_caller_identity.current.account_id
}

output "kms_key_arn" {
  description = "ARN of the fixture KMS key the test bucket is encrypted with"
  value       = data.aws_kms_alias.fixture.target_key_arn
}
