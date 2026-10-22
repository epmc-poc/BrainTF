output "role_arn" {
  description = "ARN of the role the integration tests assume (also written to TF_TEST_ROLE_ARN)"
  value       = aws_iam_role.ci.arn
}

output "kms_key_alias" {
  description = "Alias of the fixture KMS key the bucket integration test looks up"
  value       = aws_kms_alias.fixture.name
}

output "github_oidc_subjects" {
  description = "OIDC sub claims the test role trusts"
  value       = local.subjects
}
