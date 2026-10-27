# ======================= Account-level shared OIDC providers =======================
# An IAM OIDC provider is unique per issuer URL per AWS account. These providers are
# therefore created ONCE per account by this module and reused by every BrainTF
# instance (the main_module references them via a data source, it does not create them).

# Fetch the issuer TLS thumbprint for each provider.
data "external" "thumbprint" {
  for_each = var.oidc_providers
  program  = ["bash", "${path.module}/get_thumbprint.sh", each.value.url]
}

resource "aws_iam_openid_connect_provider" "this" {
  for_each        = var.oidc_providers
  url             = "https://${each.value.url}"
  client_id_list  = each.value.client_id_list
  thumbprint_list = [data.external.thumbprint[each.key].result.thumbprint]
}
