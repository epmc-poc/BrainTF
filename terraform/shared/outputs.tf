output "oidc_provider_arns" {
  description = "Map of created OIDC provider ARNs keyed by provider name."
  value       = { for k, v in aws_iam_openid_connect_provider.this : k => v.arn }
}

output "state_bucket_name" {
  description = "Name of the shared Terraform state bucket (use with -backend-config=bucket=...)."
  value       = module.state_bucket.s3_bucket_id
}

output "state_bucket_arn" {
  description = "ARN of the shared Terraform state bucket."
  value       = module.state_bucket.s3_bucket_arn
}

output "state_kms_key_arn" {
  description = "ARN of the shared KMS key used for state encryption."
  value       = module.state_kms_key.key_arn
}
