# ======================= Terraform state backend (partial configuration) =======================
# The shared account-level state bucket (created once by terraform/shared) holds
# every instance's state under <instance_id>/ key prefixes. No bucket/key is
# hardcoded here — supply them at init time:
#
#   terraform init \
#     -backend-config="bucket=braintf-state-<account_id>-<region>" \
#     -backend-config="key=<instance_id>/main-module/terraform.tfstate" \
#     -backend-config="region=<region>" \
#     -backend-config="encrypt=true" \
#     -backend-config="use_lockfile=true"
#
# State objects are encrypted by the shared bucket's default SSE-KMS
# configuration, so no kms_key_id is required for this backend.
terraform {
  backend "s3" {}
}
