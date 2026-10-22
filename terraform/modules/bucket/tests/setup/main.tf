# Per-run fixtures. The KMS key is long-lived: a deleted key stays pending deletion for 7 days.

data "aws_caller_identity" "current" {}

data "aws_kms_alias" "fixture" {
  name = var.kms_key_alias
}

resource "random_id" "suffix" {
  byte_length = 3
}
