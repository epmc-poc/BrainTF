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
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    effect = "Allow"
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_Comment_${var.vcs_repo_name}",
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_TF_Errors_${var.vcs_repo_name}"
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
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}/*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "s3:DeleteObject",
      "s3:DeleteBucketLifecycle",
      "s3:PutBucketLifecycleConfiguration",
      "s3:GetBucketLifecycleConfiguration",
    ]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}/artifacts/*"]
    effect    = "Allow"
  }
  statement {
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:ListAliases",
      "kms:ListKeys",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]
    resources = [var.kms_key_arn]
    effect    = "Allow"
  }

  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
      "ssm:DescribeParameters",
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ssm:${var.region}:${var.account_id}:parameter/*"
    ]
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
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
      "dynamodb:BatchWriteItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${var.account_id}:table/*",
      "arn:aws:dynamodb:${var.region}:${var.account_id}:table/*/index/*"
    ]
  }
  # checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"; false positive
  # checkov:skip=CKV_AWS_356: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"; false positive
}

#resource "aws_iam_policy" "lambda_exec_policy" {
#  count       = var.ai_handler_create ? 1 : 0
#  name        = "Terraform-AI-Handler-Policy-${var.vcs_repo_name}-${var.region}"
#  description = "Allow Lambda function execution"
#  policy      = data.aws_iam_policy_document.lambda_exec_policy.json
#  tags        = var.tags
#}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  count       = var.ai_handler_create ? 1 : 0
  role        = aws_iam_role.lambda_exec_role
  name        = "Terraform-AI-Handler-Policy-${var.vcs_repo_name}-${var.region}"
  policy = jsonencode(
    {
    "Statement": [
        {
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogStream",
                "logs:CreateLogGroup"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_TF_Errors_${var.vcs_repo_name}",
                "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/AI_Handler_Comment_${var.vcs_repo_name}"
            ]
        },
        {
            "Action": "s3:ListBucket",
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::ai-handler-artifacts-bucket-${var.vcs_repo_name}-${var.region}"
        },
        {
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::ai-handler-artifacts-bucket-${var.vcs_repo_name}-${var.region}/*"
        },
        {
            "Action": [
                "s3:PutBucketLifecycleConfiguration",
                "s3:GetBucketLifecycleConfiguration",
                "s3:DeleteObject",
                "s3:DeleteBucketLifecycle"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::ai-handler-artifacts-bucket-${var.vcs_repo_name}-${var.region}/artifacts/*"
        },
        {
            "Action": [
                "kms:ScheduleKeyDeletion",
                "kms:ReEncrypt*",
                "kms:ListKeys",
                "kms:ListAliases",
                "kms:GenerateDataKey*",
                "kms:Encrypt",
                "kms:DescribeKey",
                "kms:Decrypt",
                "kms:CancelKeyDeletion"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:kms:${var.region}:${var.account_id}:key/${var.kms_key_arn}"
        },
        {
            "Action": [
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter",
                "ssm:DescribeParameters"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:ssm:${var.region}:${var.account_id}:parameter/*"
        },
        {
            "Action": [
                "ec2:GetSecurityGroupsForVpc",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:CreateNetworkInterface"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "dynamodb:UpdateItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:DescribeTable",
                "dynamodb:DeleteItem",
                "dynamodb:BatchWriteItem"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:dynamodb:${var.region}:${var.account_id}:table/*/index/*",
                "arn:aws:dynamodb:${var.region}:${var.account_id}:table/*"
            ]
        }
    ],
    "Version": "2012-10-17"
}
  )
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attach" {
  count      = var.ai_handler_create ? 1 : 0
  role       = aws_iam_role.lambda_exec_role[count.index].name
  policy_arn = aws_iam_role_policy.lambda_exec_policy[count.index].arn
}

resource "aws_iam_role_policy_attachment" "basic_lambda_policy" {
  count      = var.ai_handler_create ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec_role[count.index].name
}
