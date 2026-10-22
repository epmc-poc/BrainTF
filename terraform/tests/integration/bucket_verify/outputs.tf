output "objects" {
  description = "Encryption and versioning details of each expected object, as reported by S3"
  value = {
    for key, object in data.aws_s3_object.this : key => {
      server_side_encryption = object.server_side_encryption
      sse_kms_key_id         = object.sse_kms_key_id
      version_id             = object.version_id
    }
  }
}

output "policy" {
  description = "Bucket policy JSON as stored in S3"
  value       = data.aws_s3_bucket_policy.this.policy
}
