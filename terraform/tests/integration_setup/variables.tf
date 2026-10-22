variable "vcs_project_path" {
  description = "Repository whose GitHub Actions run the integration tests, as owner/name; the same variable as in main_module"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.vcs_project_path))
    error_message = "vcs_project_path must have the form owner/name."
  }
}

variable "vcs_token" {
  description = "GitHub token allowed to write Actions variables of vcs_project_path; the same variable as in main_module"
  type        = string
  sensitive   = true
}

variable "github_oidc_subjects" {
  description = "OIDC sub claims allowed to assume the test role. Empty means pull requests of vcs_project_path and pushes to its main branch, in both GitHub claim formats"
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  description = "Prefix of every resource the integration tests may create; the test role is limited to it"
  type        = string
  default     = "braintf-tftest"
}

variable "project_tag" {
  description = "Value of the Project tag on the resources of this configuration"
  type        = string
  default     = "BrainTF"
}
