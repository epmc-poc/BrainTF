# oidc

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.oidc_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.vcs_oidc_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.vcs_oidc_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.oidc_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vcs_assume_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_artifacts_bucket"></a> [artifacts\_bucket](#input\_artifacts\_bucket) | The name of the S3 bucket for artifacts | `string` | n/a | yes |
| <a name="input_aud_variable"></a> [aud\_variable](#input\_aud\_variable) | The audience variable for the OIDC provider | `string` | n/a | yes |
| <a name="input_client_id_list"></a> [client\_id\_list](#input\_client\_id\_list) | List of client IDs for the OIDC provider | `list(string)` | n/a | yes |
| <a name="input_instance_id"></a> [instance\_id](#input\_instance\_id) | Instance identifier — the deploy role's state access is scoped to the <instance\_id>/ prefix inside the shared state bucket | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | The ARN of the KMS key for encryption | `string` | n/a | yes |
| <a name="input_managed_state_bucket"></a> [managed\_state\_bucket](#input\_managed\_state\_bucket) | The name of the S3 bucket used for the managed workload Terraform state | `string` | n/a | yes |
| <a name="input_oidc_policy_name"></a> [oidc\_policy\_name](#input\_oidc\_policy\_name) | The name of the IAM policy to create | `string` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the shared, account-level IAM OIDC provider (created by terraform/shared/) that this instance role trusts. | `string` | n/a | yes |
| <a name="input_oidc_role_name"></a> [oidc\_role\_name](#input\_oidc\_role\_name) | The name of the IAM role to create | `string` | n/a | yes |
| <a name="input_permissions_boundary"></a> [permissions\_boundary](#input\_permissions\_boundary) | ARN of the IAM permissions boundary to attach to the OIDC role. Required in accounts whose user boundary allows iam:CreateRole only when the new role carries a specific boundary. Empty = no boundary. | `string` | `""` | no |
| <a name="input_sub_values"></a> [sub\_values](#input\_sub\_values) | The subject values for the OIDC provider | `list(string)` | n/a | yes |
| <a name="input_sub_variable"></a> [sub\_variable](#input\_sub\_variable) | The subject variable for the OIDC provider | `string` | n/a | yes |
| <a name="input_vcs_provider"></a> [vcs\_provider](#input\_vcs\_provider) | The VCS provider (e.g., github, gitlab) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oidc_role_arn"></a> [oidc\_role\_arn](#output\_oidc\_role\_arn) | The oidc role arn |
<!-- END_TF_DOCS -->
