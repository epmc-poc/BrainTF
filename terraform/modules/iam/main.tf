#======================= IAM for AI Handler =======================#
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  count              = var.ai_handler_create ? 1 : 0
  name               = "Terraform-AI-Handler-Role-${var.vcs_repo_name}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_exec_policy" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    effect = "Allow"
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_Comment_${var.vcs_repo_name}:*",
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_TF_Errors_${var.vcs_repo_name}:*"
    ]
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}/logs/*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}/artifacts/*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "ssm:GetParameter",
    ]
    effect    = "Allow"
    resources = var.ssm_parameter_arns
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
      "ec2:GetSecurityGroupsForVpc"
    ]
    resources = ["*"]
  }
  # checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"; false positive
  # checkov:skip=CKV_AWS_356: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"; false positive
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
      "dynamodb:PutItem",
    ]
    resources = [
      var.dynamodb_table_arn,
    ]
  }
  # checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"; false positive
  # checkov:skip=CKV_AWS_356: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"; false positive
}

resource "aws_iam_policy" "lambda_exec_policy" {
  count       = var.ai_handler_create ? 1 : 0
  name        = "Terraform-AI-Handler-Policy-${var.vcs_repo_name}-${var.region}"
  description = "Allow Lambda function execution"
  policy      = data.aws_iam_policy_document.lambda_exec_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attach" {
  count      = var.ai_handler_create ? 1 : 0
  role       = aws_iam_role.lambda_exec_role[count.index].name
  policy_arn = aws_iam_policy.lambda_exec_policy[count.index].arn
}
