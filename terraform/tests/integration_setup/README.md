# Integration test prerequisites

Applied once per test AWS account, by someone with IAM rights in it and a GitHub token that may write Actions variables of the repository. It creates the IAM role the integration tests assume through GitHub OIDC (limited to resources named `braintf-tftest-*`), the fixture KMS key `alias/braintf-tftest`, and the repository variables `TF_TEST_ROLE_ARN` and `TF_TEST_AWS_REGION` that `.github/workflows/terraform-tests.yml` reads. See [docs/terraform_testing.md](../../../docs/terraform_testing.md#integration-tests).

The account must already have the GitHub OIDC provider; BrainTF `main_module` creates it.

It reads `vcs_project_path` and `vcs_token` from the same files `main_module` uses, so nothing has to be copied:

```bash
terraform init
terraform apply -var-file=../../main_module/terraform.tfvars -var-file=../../main_module/secrets.auto.tfvars
```

Terraform warns about the other values in those files ("Value for undeclared variable"); that is expected.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.66 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.13 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.66 |
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.13 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.ci](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ci](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.fixture](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.fixture](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [github_actions_variable.region](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.role_arn](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_openid_connect_provider) | data source |
| [aws_iam_policy_document.ci](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_github_oidc_subjects"></a> [github\_oidc\_subjects](#input\_github\_oidc\_subjects) | OIDC sub claims allowed to assume the test role. Empty means pull requests of vcs\_project\_path and pushes to its main branch, in both GitHub claim formats | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource the integration tests may create; the test role is limited to it | `string` | `"braintf-tftest"` | no |
| <a name="input_project_tag"></a> [project\_tag](#input\_project\_tag) | Value of the Project tag on the resources of this configuration | `string` | `"BrainTF"` | no |
| <a name="input_vcs_project_path"></a> [vcs\_project\_path](#input\_vcs\_project\_path) | Repository whose GitHub Actions run the integration tests, as owner/name; the same variable as in main\_module | `string` | n/a | yes |
| <a name="input_vcs_token"></a> [vcs\_token](#input\_vcs\_token) | GitHub token allowed to write Actions variables of vcs\_project\_path; the same variable as in main\_module | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_github_oidc_subjects"></a> [github\_oidc\_subjects](#output\_github\_oidc\_subjects) | OIDC sub claims the test role trusts |
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | Alias of the fixture KMS key the bucket integration test looks up |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the role the integration tests assume (also written to TF\_TEST\_ROLE\_ARN) |
<!-- END_TF_DOCS -->
