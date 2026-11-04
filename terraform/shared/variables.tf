variable "oidc_providers" {
  description = <<-EOT
    Map of account-level IAM OIDC identity providers to create, keyed by a short
    name (e.g. "github", "gitlab"). Each OIDC issuer URL may exist only once per
    AWS account, so these providers are shared by all BrainTF instances of the
    same VCS type. Instance-level roles (created by the main_module) reference
    these providers and must NOT recreate them.
  EOT
  type = map(object({
    url            = string       # issuer host without scheme, e.g. "token.actions.githubusercontent.com"
    client_id_list = list(string) # audience(s), e.g. ["sts.amazonaws.com"] for GitHub
  }))
  default = {
    github = {
      url            = "token.actions.githubusercontent.com"
      client_id_list = ["sts.amazonaws.com"]
    }
  }
}

variable "state_bucket_prefix" {
  description = "Prefix for the shared Terraform state bucket name: <prefix>-<account_id>-<region>. One bucket per AWS account; instance states live under <instance_id>/ key prefixes."
  type        = string
  default     = "braintf-state"
}

variable "owner_mail" {
  description = "The owner e-mail. Optional when the deployer's AWS identity is named after an e-mail (e.g. IAM user name@epam.com); in that case it is derived automatically. Set explicitly to override."
  type        = string
  default     = ""

  validation {
    condition     = var.owner_mail == "" || can(regex("@", var.owner_mail))
    error_message = "owner_mail must be empty or a valid e-mail address."
  }
}
