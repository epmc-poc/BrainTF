# Terraform tests

Native `terraform test` suites for BrainTF's own Terraform code. Details, conventions and the test catalogue: [docs/terraform_testing.md](../../docs/terraform_testing.md).

| Folder | What | AWS |
|---|---|---|
| `unit/` | One test file per configuration (`bootstrap`, `main_module`, `modules/oidc`, `modules/bucket`); each `run` names the module it tests | None; mocked providers, no network |
| `integration/` | Real resources in the test account, destroyed at the end; helper modules `bucket_setup` and `bucket_verify` | OIDC role from `integration/account_setup` |
| `integration/account_setup/` | Applied once per test account: CI role, fixture KMS key, GitHub variables | IAM rights in the test account |
| `mocks/aws/` | Shared mock data of the AWS provider | |

Run from anywhere in the repository:

```bash
scripts/terraform_tests.sh unit
scripts/terraform_tests.sh integration
scripts/terraform_tests.sh all
scripts/terraform_tests.sh account-setup plan      # or apply / destroy
```
