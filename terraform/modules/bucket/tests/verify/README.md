# Read-back checks for the bucket integration test

Helper module for `tests/integration`: data sources only, so the test can assert on what S3 actually stored. Not used outside the tests.

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
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_bucket_policy) | data source |
| [aws_s3_object.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_object) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the bucket created by the module under test | `string` | n/a | yes |
| <a name="input_object_keys"></a> [object\_keys](#input\_object\_keys) | Keys of objects expected in the bucket | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_objects"></a> [objects](#output\_objects) | Encryption and versioning details of each expected object, as reported by S3 |
| <a name="output_policy"></a> [policy](#output\_policy) | Bucket policy JSON as stored in S3 |
<!-- END_TF_DOCS -->
