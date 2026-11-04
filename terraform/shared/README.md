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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.66 |
| <a name="requirement_external"></a> [external](#requirement\_external) | ~> 2.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.66 |
| <a name="provider_external"></a> [external](#provider\_external) | ~> 2.2 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_state_bucket"></a> [state\_bucket](#module\_state\_bucket) | git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git | 6c5e082b5d2fde77cb59c387a7f553dd2ed5da29 |
| <a name="module_state_kms_key"></a> [state\_kms\_key](#module\_state\_kms\_key) | git::https://github.com/terraform-aws-modules/terraform-aws-kms.git | 407e3db34a65b384c20ef718f55d9ceacb97a846 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_s3_bucket_policy.state_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [external_external.caller_identity](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [external_external.thumbprint](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_oidc_providers"></a> [oidc\_providers](#input\_oidc\_providers) | Map of account-level IAM OIDC identity providers to create, keyed by a short<br/>name (e.g. "github", "gitlab"). Each OIDC issuer URL may exist only once per<br/>AWS account, so these providers are shared by all BrainTF instances of the<br/>same VCS type. Instance-level roles (created by the main\_module) reference<br/>these providers and must NOT recreate them. | <pre>map(object({<br/>    url            = string       # issuer host without scheme, e.g. "token.actions.githubusercontent.com"<br/>    client_id_list = list(string) # audience(s), e.g. ["sts.amazonaws.com"] for GitHub<br/>  }))</pre> | <pre>{<br/>  "github": {<br/>    "client_id_list": [<br/>      "sts.amazonaws.com"<br/>    ],<br/>    "url": "token.actions.githubusercontent.com"<br/>  }<br/>}</pre> | no |
| <a name="input_owner_mail"></a> [owner\_mail](#input\_owner\_mail) | The owner e-mail. Optional when the deployer's AWS identity is named after an e-mail (e.g. IAM user name@epam.com); in that case it is derived automatically. Set explicitly to override. | `string` | `""` | no |
| <a name="input_state_bucket_prefix"></a> [state\_bucket\_prefix](#input\_state\_bucket\_prefix) | Prefix for the shared Terraform state bucket name: <prefix>-<account\_id>-<region>. One bucket per AWS account; instance states live under <instance\_id>/ key prefixes. | `string` | `"braintf-state"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oidc_provider_arns"></a> [oidc\_provider\_arns](#output\_oidc\_provider\_arns) | Map of created OIDC provider ARNs keyed by provider name. |
| <a name="output_state_bucket_arn"></a> [state\_bucket\_arn](#output\_state\_bucket\_arn) | ARN of the shared Terraform state bucket. |
| <a name="output_state_bucket_name"></a> [state\_bucket\_name](#output\_state\_bucket\_name) | Name of the shared Terraform state bucket (use with -backend-config=bucket=...). |
| <a name="output_state_kms_key_arn"></a> [state\_kms\_key\_arn](#output\_state\_kms\_key\_arn) | ARN of the shared KMS key used for state encryption. |
<!-- END_TF_DOCS -->
