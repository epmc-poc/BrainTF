variable "region" {
  description = "The AWS Region where infrastructure resources will be deployed"
  type        = string
}

variable "instance_id" {
  description = "Instance identifier used for resource naming"
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

variable "kms_key_arn" {
  description = "The ARN of the KMS key used for bucket encryption"
  type        = string
}

variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table for AI chat history (used to scope the Lambda policy to this instance's table)"
  type        = string
}
