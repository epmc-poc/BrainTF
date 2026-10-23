variable "bucket_name" {
  description = "Name of the bucket created by the module under test"
  type        = string
}

variable "object_keys" {
  description = "Keys of objects expected in the bucket"
  type        = list(string)
}
