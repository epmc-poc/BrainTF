# Lambda execution role permissions

Defined in `terraform/modules/iam/main.tf` (`aws_iam_policy_document.lambda_exec_policy`).
Both Lambdas (`AI_Handler_TF_Errors_*` and `AI_Handler_Comment_*`) share one role.

Status legend:
- **Confirmed**: visible in the repository code or configuration.
- **Assumed**: inferred from how the AWS service behaves; not yet verified in a deployed environment
  (verify with CloudTrail, see "How to verify").

This page is built up step by step, one permission area per change. Areas not listed here have not been reviewed yet.

## KMS (key: `var.kms_key_arn`)

The Python code never calls KMS directly (no `kms` in `terraform/modules/lambdas/functions/`).
KMS is used on the role's behalf by other services.

| Action | Used for | Used by | Status |
|---|---|---|---|
| `kms:Decrypt` | Reading objects from the artifacts bucket (`logs/` and `artifacts/`) and reading chat history from DynamoDB | TF-errors Lambda (reads `logs/`, `get_file_content_with_metadata_from_s3`); Comment Lambda (`/show`, `/diff`, `/approve`, `/prompt`) | Encryption config **confirmed** (`modules/bucket/main.tf:19-20`, `modules/dynamodb/main.tf:11`); the need for this action on the caller **assumed** |
| `kms:GenerateDataKey*` | Writing encrypted data: S3 `put_object` and DynamoDB `PutItem` | TF-errors Lambda (`upload_files_to_s3`); both Lambdas (`transact_write_items` in `put_messages_to_db`) | Encryption config **confirmed**; the need for this action **assumed** |
| `kms:DescribeKey` | Key lookup by AWS services acting for the caller | Not traced to a code path | **Assumed** (kept to stay safe; candidate for removal if CloudTrail shows no use) |

Notes:
- SSM parameters are `SecureString` but the `ssm_parameters` module call in `main_module/main.tf` sets no `key_id`,
  so they most likely use the default `aws/ssm` key and do **not** depend on this permission (**assumed**; confirm the module default).
- `kms_key_arn` is also passed to the Lambda module to encrypt environment variables. Whether the execution role
  needs anything for that is **not confirmed**.

## How to verify
In CloudTrail Event history (same region as the key), filter by **Event source = `kms.amazonaws.com`** after exercising
`/prompt`, `/list`, `/show`, `/diff`, `/approve` and a failing Terraform run. The event names show which actions are used;
`errorCode: AccessDenied` shows a missing permission. Update the **Status** column above with the result.
