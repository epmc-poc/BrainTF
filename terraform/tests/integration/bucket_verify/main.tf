# Data sources only: reads back what S3 actually stored.

data "aws_s3_object" "this" {
  for_each = toset(var.object_keys)

  bucket = var.bucket_name
  key    = each.value
}

data "aws_s3_bucket_policy" "this" {
  bucket = var.bucket_name
}
