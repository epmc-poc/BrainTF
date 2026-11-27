# Lambda execution role permissions

Defined in `terraform/modules/iam/main.tf` (`aws_iam_policy_document.lambda_exec_policy`).
Both Lambdas (`AI_Handler_TF_Errors_*` and `AI_Handler_Comment_*`) share one role.

Status legend:
- **Confirmed**: visible in the repository code or configuration.
- **Assumed**: inferred from how the AWS service behaves; not yet verified in a deployed environment
  (verify with CloudTrail, see "How to verify").

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

### How to verify
Run a failing pipeline, `/show` and `/prompt` in a dev account. In CloudTrail Event history, filter
`Event source = kms.amazonaws.com`: the event names under the role show which actions are used.
To prove one is needed, remove it and expect `AccessDenied` (Lambda logs, CloudTrail `errorCode`).

## SSM (parameters created by `module "ssm_parameters"`)

| Action | Resource | Used for | Used by | Status |
|---|---|---|---|---|
| `ssm:GetParameter` | ARNs of the three parameters, taken from the `ssm_parameters` module outputs (`ssm_parameter_arns` input of the `iam` module) | Reading three `SecureString` parameters with `WithDecryption=True`: `/<repo>/vcs_token`, `/<repo>/ai_token`, `/<repo>/webhook_secret` (`config.py`) | VCS token: both Lambdas (VCS API calls). AI token: both Lambdas (`chat_completions.py:48`). Webhook secret: Comment Lambda only (`utilities/auth.py:58`, `:63`) | **Confirmed** (direct `get_parameter` calls; the ARNs come from the parameters Terraform creates) |

The Python code only calls `get_parameter`, so `GetParameters`, `GetParametersByPath` and `DescribeParameters` are not granted.
The ARNs come from the module outputs, so the policy follows the real parameters. A parameter added to `local.ssm_parameters`
in `main_module/main.tf` is covered automatically; one created outside that module is not.

### How to verify
Post a PR/MR comment (reads the webhook secret and the VCS token) and run `/prompt` (reads the AI token).
To prove the scope is right, remove one parameter ARN from the policy and expect `AccessDenied` (`ClientError`) in the Lambda logs.
SSM calls are management events, so they are listed in CloudTrail Event history (`Event source = ssm.amazonaws.com`).

## S3 (bucket: `var.artifacts_bucket`)
The policy uses the default prefix `artifacts/` (the Lambdas' `ARTIFACTS_PATH`, default `artifacts`). It does not follow a custom
`artifacts_path`: the S3 lifecycle rule and the placeholder directory in `main_module/main.tf` are hardcoded to `artifacts/` too.
The `logs/` prefix is fixed in the S3 notification in `modules/lambdas/main.tf`.

| Action | Resource | Used for | Used by | Status |
|---|---|---|---|---|
| `s3:GetObject` | `<bucket>/logs/*` | Reading the pipeline log that triggered the Lambda: `get_file_content_with_metadata_from_s3` (`get_object`, `head_object`; `head_object` is authorized by `s3:GetObject`) | TF-errors Lambda | **Confirmed** (direct calls in `utilities/aws.py`) |
| `s3:GetObject` | `<bucket>/artifacts/*` | Reading stored fixes: `get_all_files_from_s3_directory`, `get_particular_files_from_s3_directory` | Comment Lambda (`/show`, `/diff`, `/approve`) | **Confirmed** |
| `s3:PutObject` | `<bucket>/artifacts/*` | Storing corrected files: `upload_files_to_s3` (`put_object`, key `artifacts/<pr>/<file>`) | TF-errors Lambda (`handle_ai_response_message`) | **Confirmed** |
| `s3:DeleteObject` | `<bucket>/artifacts/*` | Deleting stored artifacts: `delete_files_from_s3` calls `delete_objects` | TF-errors Lambda (clears old artifacts before uploading new ones, `handlers.py:64`); Comment Lambda (`/approve`, `handlers.py:425`, `:463`) | **Confirmed** |
| `s3:ListBucket` | the bucket (no prefix condition) | Listing artifacts: `list_objects_v2` with `Prefix=artifacts/<id>/` in `get_file_names_from_s3_directory`, `get_all_files_from_s3_directory`, `delete_files_from_s3` | Both Lambdas | **Confirmed** (direct calls). Kept unscoped: the bucket is created by this project and holds only `logs/` and `artifacts/`, and the role can already read `logs/` |

Notes:
- Neither Lambda writes to `logs/`; the pipeline uploads the logs with its own (OIDC) role.

### How to verify
Run a failing pipeline (reads `logs/`, writes and deletes under `artifacts/`), then `/list`, `/show`, `/diff` and `/approve`
(read, list and delete). To prove a scope is right, remove one statement and expect `AccessDenied` in the Lambda logs.
Event history does not list object-level S3 calls (data events); enable S3 data events to see them.

## DynamoDB (table: chat history, `module "ai_dynamodb_table"`)

| Action | Resource | Used for | Used by | Status |
|---|---|---|---|---|
| `dynamodb:Query` | Table ARN, taken from the `dynamodb` module output (`dynamodb_table_arn` input of the `iam` module) | Reading the chat history for a commit: `get_messages_from_db` calls `table.query` (`utilities/aws.py`) | Comment Lambda (`/prompt`, `get_context_memory_window`, `handlers.py:322`) | **Confirmed** (direct call) |
| `dynamodb:PutItem` | Same table ARN | Saving messages: `put_messages_to_db` calls `transact_write_items` with `Put` items | TF-errors Lambda (`create_context_memory_window`); Comment Lambda (`handlers.py:337`) | Call **confirmed**; that a transactional `Put` needs only `PutItem` is **assumed** from AWS behavior |

Only the table ARN is granted, with no `/index/*`: the table has no secondary index. If one is added, add its ARN
(`<table_arn>/index/<name>`) to the policy. Read, scan, update and delete actions are not granted because the code does not call them.

### How to verify
Run `/prompt` twice on the same commit: the second answer keeps the context, so both the read (`Query`) and the write (`PutItem`) work.
To prove each action is needed, remove it and expect `AccessDenied` in the Lambda logs.
DynamoDB item-level calls are data events, so they do not appear in CloudTrail Event history.

## CloudWatch Logs (log groups `/aws/lambda/AI_Handler_TF_Errors_<repo>` and `/aws/lambda/AI_Handler_Comment_<repo>`)

| Action | Resource | Used for | Used by | Status |
|---|---|---|---|---|
| `logs:CreateLogStream` | `<log group ARN>:*` | Lambda runtime creates a log stream per execution environment | Both Lambdas | **Confirmed** (Lambda runtime behavior); the Lambda module sets `create_role = false` |
| `logs:PutLogEvents` | `<log group ARN>:*` | Lambda runtime writes the function output and logs | Both Lambdas | **Confirmed** |

- The log groups are created by the `terraform-aws-lambda` module (`aws_cloudwatch_log_group.lambda`), not by the function at runtime,
  so `logs:CreateLogGroup` is not granted.
- The ARN ends with `:*` because log streams are sub-resources of the log group. Before this change the ARNs had no `:*`,
  so this statement never matched, and logging worked only through the managed `AWSLambdaBasicExecutionRole`
  (`logs:*` actions on `Resource: "*"`). That attachment is removed, so the statement is now the only source of log permissions.
- Behavior change: the Lambdas can no longer recreate a log group that was deleted by hand (the managed policy allowed
  `logs:CreateLogGroup` on `*`). Such a group is Terraform drift: logs stop until the next `terraform apply` recreates it.
  A group recreated by the Lambda would have no retention and would sit outside Terraform state, so the next `apply` would fail with "already exists".
- If a log group is renamed or the Lambda module stops creating it, update this statement.

### How to verify
After deploying, invoke each Lambda once (a failing pipeline and a bot comment) and check that new streams and events appear in both log groups.
Missing logs plus no `AccessDenied` visible in the function means the permission is wrong: check the Lambda console Monitor tab and CloudTrail
(`logs.amazonaws.com`, `errorCode`).
