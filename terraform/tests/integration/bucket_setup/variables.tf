variable "run_id" {
  description = "Identifier of the test run, part of every resource name (CI passes the workflow run id)"
  type        = string
  default     = "local"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.run_id))
    error_message = "run_id must be 1-20 characters of lowercase letters, digits and dashes."
  }
}

variable "name_prefix" {
  description = "Prefix of every test resource name; the test IAM role is limited to it"
  type        = string
  default     = "braintf-tftest"
}

variable "kms_key_alias" {
  description = "Alias of the fixture KMS key in the test account used to encrypt test buckets"
  type        = string
  default     = "alias/braintf-tftest"
}
