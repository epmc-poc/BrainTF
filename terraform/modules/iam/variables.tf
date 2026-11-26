variable "region" {
  description = "The AWS Region where infrastructure resources will be deployed"
  type        = string
}

variable "vcs_repo_name" {
  description = "Project name used for resource tagging and naming"
  type        = string
}

variable "artifacts_bucket" {
  description = "The artifacts bucket name"
  type        = string
}

variable "ai_handler_create" {
  description = "Whether to create AI handler webhooks."
  type        = bool
  default     = false
}

variable "account_id" {
  description = "The AWS account ID where the infrastructure will be deployed"
  type        = string
}

variable "ssm_parameter_arns" {
  description = "The ARNs of the SSM parameters the Lambda functions may read"
  type        = list(string)
}

variable "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table with the AI chat history"
  type        = string
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key used for bucket encryption"
  type        = string
}
