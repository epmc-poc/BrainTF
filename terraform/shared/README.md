# Shared (account-level) resources

This root module provisions resources that are **shared by all BrainTF instances in an
AWS account** and must exist exactly once. It is applied **once per account**, before any
instance's `bootstrap` / `main_module`.

## What it creates

- **IAM OIDC identity provider(s)** for the VCS CI/CD (e.g. GitHub Actions
  `token.actions.githubusercontent.com`). An OIDC provider is unique per issuer URL per
  account, so it cannot be created per instance. Instance-level IAM roles (created by the
  `main_module`) reference these providers via a data source and must not recreate them.

## Usage

```bash
cd terraform/shared
terraform init
terraform apply
```

By default only the GitHub provider is created. To also create a GitLab provider (or a
self-managed GitLab), override `oidc_providers`:

```hcl
# terraform/shared/terraform.tfvars
oidc_providers = {
  github = {
    url            = "token.actions.githubusercontent.com"
    client_id_list = ["sts.amazonaws.com"]
  }
  gitlab = {
    url            = "gitlab.com"
    client_id_list = ["https://gitlab.com"]
  }
}
```

> If an OIDC provider for the issuer already exists in the account (created outside this
> module), import it (`terraform import`) or remove that key from `oidc_providers` so the
> instance `main_module` can still resolve it via its data source.

## Lifecycle

These providers must **survive** destruction of any single instance. Do not run
`terraform destroy` here while any instance still depends on the provider.
