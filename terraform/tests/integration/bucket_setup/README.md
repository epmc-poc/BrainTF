# Test fixtures for the bucket integration test

Helper module for `bucket.tftest.hcl` in the parent folder: a unique bucket name for the run and the fixture KMS key of the test account. Not used outside the tests.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.9 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.9 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_kms_alias.fixture](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | Alias of the fixture KMS key in the test account used to encrypt test buckets | `string` | `"alias/braintf-tftest"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every test resource name; the test IAM role is limited to it | `string` | `"braintf-tftest"` | no |
| <a name="input_run_id"></a> [run\_id](#input\_run\_id) | Identifier of the test run, part of every resource name (CI passes the workflow run id) | `string` | `"local"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | ID of the AWS account the test runs in |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Unique bucket name for this test run |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the fixture KMS key the test bucket is encrypted with |
<!-- END_TF_DOCS -->
