output "oidc_provider_arns" {
  description = "Map of created OIDC provider ARNs keyed by provider name."
  value       = { for k, v in aws_iam_openid_connect_provider.this : k => v.arn }
}
