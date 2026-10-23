# Shared AWS mock data for the unit tests. Mock blocks cannot use variables, so the fake values live here once.

mock_data "aws_region" {
  defaults = {
    region = "eu-west-1"
  }
}

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:user/terraform-test"
  }
}

# Otherwise the mock returns a random string, which fails policy JSON validation.
mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_kms_alias" {
  defaults = {
    arn            = "arn:aws:kms:eu-west-1:123456789012:alias/terraform-test"
    target_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }
}
