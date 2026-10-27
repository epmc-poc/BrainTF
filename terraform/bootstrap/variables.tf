variable "instance_id" {
  description = "Immutable, account-unique identifier for this BrainTF instance. Independent of the repository name; used to namespace all instance-scoped AWS resources (state bucket, KMS alias, IAM role)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.instance_id))
    error_message = "instance_id must be lowercase alphanumeric with hyphens, 1-30 chars, and may not start or end with a hyphen."
  }
}

variable "vcs_repo_name" {
  description = "The Project name (used for tagging only)"
  type        = string
}

variable "environment" {
  description = "The Project environment"
  type        = string
}

variable "team" {
  description = "The owner team"
  type        = string
}

variable "deployed_by" {
  description = "The deployment method"
  type        = string
}

variable "owner_mail" {
  description = "The owner e-mail"
  type        = string
}

variable "platform_state_bucket_prefix" {
  description = "Custom prefix for the platform state S3 bucket name (stores state of bootstrap + main_module)"
  type        = string
  default     = "backend-state-bucket"
}
