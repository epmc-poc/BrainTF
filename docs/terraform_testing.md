# Terraform tests

BrainTF's own Terraform code is tested with the native `terraform test` command in a dedicated developer pipeline, [`.github/workflows/terraform-tests.yml`](../.github/workflows/terraform-tests.yml). There are two kinds of tests. **Unit tests**, for `terraform/bootstrap` and `terraform/main_module`, need no AWS credentials and create nothing in any cloud account; they run on every pull request. One **integration test**, for `terraform/modules/bucket`, creates a real bucket in a test AWS account, checks it and removes it again; it runs only on request.

The existing pipelines are unchanged. `pipeline.yml` keeps scanning the demo workload in `WORK_DIRS`, and `developer-pipeline.yml` keeps running the Python tests of the Lambda functions.

## Contents

- [How a unit test runs without AWS](#how-a-unit-test-runs-without-aws)
- [What deserves a unit test](#what-deserves-a-unit-test)
- [Developer pipeline](#developer-pipeline)
- [Layout and conventions](#layout-and-conventions)
- [Running the tests locally](#running-the-tests-locally)
- [Coverage report](#coverage-report)
- [Integration tests](#integration-tests)
- [Test account setup](#test-account-setup)
- [Test catalogue](#test-catalogue)
- [Open findings](#open-findings)
- [Prerequisites and constraints](#prerequisites-and-constraints)
- [Known risks and limitations](#known-risks-and-limitations)
- [Plan for further implementation](#plan-for-further-implementation)
- [What we took from the HashiCorp tutorial](#what-we-took-from-the-hashicorp-tutorial)

## How a unit test runs without AWS

`terraform test` reads the `*.tftest.hcl` files of a configuration and executes their `run` blocks in order. Each `run` is a `plan` (or an `apply`) of the configuration with the variables the test sets, followed by its `assert` blocks. State lives in memory only; the S3 backend is never used.

Nothing reaches AWS because every provider is replaced in one of two ways:

| Technique | What it does | Used where |
|---|---|---|
| `mock_provider` | Terraform answers for the provider: computed attributes get generated values, data sources return the configured `defaults`. The real provider is still loaded for its schema and argument validation | `bootstrap`, `main_module` |
| `override_module` / `override_resource` / `override_data` | Replace a module's outputs, a resource's attributes or a data source's result with fixed values. An overridden module is not evaluated at all | Child modules of `main_module`, upstream modules of `bootstrap` |

Terraform works in two steps. First it evaluates the configuration: variables, locals, conditions, `count`, `for_each`, names, policy documents. Then the provider calls the AWS API. A unit test stops after the first step: the plan holds every planned resource with its arguments, and the assertions read those arguments. Where the configuration needs something only AWS knows (region, account id, the ARN of a bucket that does not exist yet), the mock answers with a fixed value. A test therefore says: with these inputs and these answers from AWS, our code computes this.

Unit tests check BrainTF's own logic: input validation, feature toggles, names other components depend on, the state bucket policy, the OIDC trust conditions, the CI variables written to the VCS, and the files bootstrap generates. They do not prove that AWS accepts a change; that needs integration tests (see the plan below).

## What deserves a unit test

A unit test is worth its upkeep when it protects a decision in BrainTF's code that something depends on or that is dangerous to get wrong:

1. **A contract with another component**: names the Lambdas read (SSM parameters), CI variables the workflows read, the state bucket name that bootstrap and main_module compute separately, the generated backend file.
2. **Security**: who may assume the pipeline role, which values are secrets, TLS-only bucket policies.
3. **Validation rules** written in `variables.tf`.
4. **Known bugs**: the `finding_*` runs.

A test that only restates a string concatenation or a `count` condition nobody relies on is not written. For example, the name of bootstrap's Terraform role is not tested: nothing else refers to it.

## Developer pipeline

`terraform-tests.yml` has two stages and a report job.

| | Stage 1: unit tests | Stage 2: integration tests | Report |
|---|---|---|---|
| Trigger | `pull_request` to `main` with changes in `terraform/**` or in the workflow; manual run (`workflow_dispatch`) | Only on request: label `tf-integration` on a pull request from this repository (forks get no OIDC token), or a manual run with `integration` checked. Skipped where the `TF_TEST_ROLE_ARN` variable is not set | After both stages, also when they failed |
| Jobs | One | One | One |
| Steps | `terraform fmt -check` on `terraform/tests`, then `terraform init`, `validate` and `test` in `terraform/tests/unit`, `scripts/normalize_terraform_junit.py`, the [coverage report](#coverage-report) in the job summary | Assume the test role through OIDC, `terraform init`, `validate` and `test` in `terraform/tests/integration`, normalize the JUnit file, leak check | Publishes all JUnit files with `dorny/test-reporter`, the action `developer-pipeline.yml` already uses |
| Access | No AWS credentials, `AWS_CONFIG_FILE`/`AWS_SHARED_CREDENTIALS_FILE` point to `/dev/null`, instance metadata disabled. `terraform test` runs in a network namespace without interfaces | Short-lived credentials of the role in `TF_TEST_ROLE_ARN` (1 hour), limited to `braintf-tftest-*` resources; region from `TF_TEST_AWS_REGION` | `checks: write` |
| Quality gate | Any failing run fails the job; meant to become a required status check | Tests pass and no bucket with the run's prefix is left behind | The check run "Terraform test results" lists every run with its result |

Both stages run plain `terraform init`, `validate` and `test` in the test folder, the same commands a developer runs locally. A running integration job is never cancelled (`cancel-in-progress: false`), because an interrupted apply leaves resources behind.

Why the JUnit file is normalized: Terraform 1.14 writes the duration only on each `<testcase>`, not on `<testsuite>`, so the report showed "NaNms"; and for a run that ends in an error (such as a missing expected failure) it writes `message="Encountered an error"` and keeps the reason in the element text, so the report showed only that phrase. `scripts/normalize_terraform_junit.py` sets the suite durations and puts "<error title>: <explanation>" into the message. It changes nothing Terraform already filled in, and uses only the Python standard library.

Why the network is cut during `terraform test` (GitHub runners do have internet access, and `init` uses it): a `mock_provider` only replaces providers that are declared in the root module under test, and `local-exec` provisioners run even for mocked resources. Both were observed while building these tests (see [Layout and conventions](#layout-and-conventions)). Without network, such a leak fails the test instead of quietly calling the internet. `terraform init` runs before that, with network, because it downloads providers and modules. GitHub's Ubuntu 24.04 runners block unprivileged user namespaces (`unshare -rn`), so the step falls back to `sudo unshare --net` and drops back to the runner user with `setpriv`.

The role of `terraform test` in BrainTF: it checks the behaviour of BrainTF's Terraform code before review. The static checks (`fmt`, `validate`, TFLint, Checkov, TFSec, Trivy in `pipeline.yml`) stay as they are; a full deployment to a test AWS account stays the end-to-end check.

## Layout and conventions

All Terraform tests live in one place, split by kind, one test file per configuration under test:

```text
terraform/tests/
  mocks/aws/aws.tfmock.hcl      shared mock data of the AWS provider
  unit/                         terraform test runs here; no AWS, no network
    versions.tf                 registry sources of the mocked providers (github, gitlab)
    bootstrap.tftest.hcl        tests terraform/bootstrap
    main_module.tftest.hcl      tests terraform/main_module
  integration/                  terraform test runs here; real AWS in the test account
    bucket.tftest.hcl           tests terraform/modules/bucket
    bucket_setup/               helper module: unique name, fixture KMS key lookup
    bucket_verify/              helper module: data sources that read the bucket back from AWS
    account_setup/              one-time test account setup (role, KMS key, GitHub variables)
```

Every `run` names the configuration it tests with a `module { source = "../../<path>" }` block, because `terraform test` otherwise tests the directory it runs in. Every test file has the same shape: a one-line header, providers and overrides, one `variables` block, the `run` blocks, and at the end the section of open findings.

**Where literal values may appear.** Test data is defined once and referenced everywhere else:

- The `variables` block at the top of the file holds the inputs of the module under test and test values used by several runs. Run blocks set only the values that differ for that run.
- Assertions contain no copies of test data. They reference variables (`var.vcs_repo_name`), data sources that return mock values (`data.aws_region.current.region`), module outputs (`module.oidc[0].oidc_role_arn`) or other attributes. Literals in assertions are limited to the contract itself: names such as `JOB_TOKEN`, values such as `SecureString` or `Deny`.
- `mock_provider`, `mock_data`, `override_*` blocks cannot use variables (Terraform rejects `var.*` there). Their values are written once: in `terraform/tests/mocks/aws/aws.tfmock.hcl` for data that several configurations share, or in a single override block per file.

**Rules learned while writing the first tests:**

1. **Set every variable in the test file.** `terraform test` loads `terraform.tfvars` and `*.auto.tfvars` from the configuration directory. Locally that includes your `secrets.auto.tfvars`; in CI those files do not exist. Values in the test file take precedence over them, so setting all of them makes local and CI runs identical. Do not create `.tfvars` files for tests: `*.tfvars` is in `.gitignore`.
2. **A `mock_provider` only replaces providers declared in the configuration under test.** `main_module` uses `external` (thumbprint script) and `null` (Lambda packaging) only inside child modules, so mocking them in a `main_module` test has no effect, and Terraform gives no warning: the script really opened a TLS connection. In `main_module` tests, replace those child modules with `override_module`, and test each module in its own test file.
3. **Provisioners run even for mocked and overridden resources.** An `apply` of `main_module` in a test ran `docker run … pip install` and packaged the Lambdas. Test `main_module` and `modules/lambdas` with `command = plan`, or override the module.
4. **Mocked values must look real.** Mocks fill computed attributes with random 8-character strings, and the provider still validates them ("invalid ARN", "invalid JSON"). Give `mock_data` realistic `defaults`.
5. **`override_resource` does not skip the provider's argument validation; `override_module` does**, because the module's resources are not evaluated. Use `override_module` when the point of a run is a value computed before a module, such as a name.
6. **Asserts only see outputs of child modules**, not their resources. Assert on root resources, locals and module outputs.
7. **Compare lists with `tolist()`.** `local.x == ["a", "b"]` fails with "LHS and RHS values are of different types"; write `local.x == tolist(["a", "b"])`.
8. **A run that ends in an error makes Terraform skip all later runs of the file.** A failed assertion does not. A missing expected failure (`expect_failures` that did not happen) is an error, which is why the open findings sit at the end of each file.
9. **Paths in `mock_provider { source = … }` and in `module { source = … }` are relative to the directory `terraform test` runs in** (`terraform/tests/unit` or `terraform/tests/integration`).
10. **Providers outside `hashicorp/` need their source declared there.** Without `terraform/tests/unit/versions.tf`, `mock_provider "github"` resolves to `hashicorp/github` and fails.

## Running the tests locally

Plain Terraform in the test folder, no extra flags: the test folders have no backend, so `init` never touches a state, and the test files sit where `terraform test` looks for them.

```bash
cd terraform/tests/unit
terraform init
terraform test                                 # all unit tests, no AWS credentials needed
terraform test -filter=main_module.tftest.hcl  # one file
```

Integration tests run the same way in `terraform/tests/integration`, with credentials for the test account. Locally the network stays on; the pipeline cuts it during the unit tests, so a mocked run that reaches the internet fails there.

If bootstrap has generated `terraform/main_module/backend.generated.tf` on your machine, Terraform prints "Backend configuration ignored" for each run; that is expected, the tests never use a backend.

## Coverage report

HCL has no line coverage like `pytest --cov`, and `terraform test` reports none. `scripts/terraform_test_coverage.py` counts instead what a reviewer can act on, for every configuration under `terraform/` (root modules and `terraform/modules/*`):

| Number | Meaning |
|---|---|
| Configurations with tests | A `run` block names the configuration in `module { source = … }` |
| Variables with validation rules that have an `expect_failures` run | Validation rules that a test proves to reject bad input |
| Objects checked by an assert | Resources, module calls, outputs, locals and `aws_iam_policy_document` data sources that at least one `assert` condition names. Lookups such as `aws_region` are not counted |

The last number is approximate: names are matched as text, and an assert that names an object does not prove it checks everything about it. The report also lists the objects no assert names and the `expect_failures` runs on variables without a validation rule (the open findings). It is informational and fails nothing. The unit job adds it to the run's Summary page; locally, from the repository root:

```bash
python3 scripts/terraform_test_coverage.py
```

## Integration tests

A unit test checks what our code computes. An integration test checks what AWS does with it: whether it accepts the configuration, in which order the resources come into existence, and what it finally stores. `terraform/tests/integration/bucket.tftest.hcl` is the first one:

| Run | What happens |
|---|---|
| `setup` | Helper module `bucket_setup`: a unique bucket name `braintf-tftest-<run_id>-<random>` and the ARN of the fixture KMS key `alias/braintf-tftest` |
| `create_bucket` | `command = apply` of the bucket module with the placeholders and lifecycle rule main_module uses. Checks the name, ARN and that AWS accepted the lifecycle rule |
| `tls_only_policy_is_attached_in_aws` | Helper module `bucket_verify` reads the bucket policy back from S3 |
| `finding_placeholder_objects_use_bucket_kms_key_and_versioning` | `bucket_verify` reads `logs/` and `artifacts/` back from S3 and expects SSE-KMS with the bucket's key and a version id. Fails today: open finding 3 |

After the last run, `terraform test` destroys everything in reverse order (`force_destroy` removes the objects and their versions). The workflow then lists buckets with the run's prefix and fails if any is left. A run takes about one minute and costs nothing measurable.

Run it locally with credentials for the test account:

```bash
cd terraform/tests/integration
terraform init
terraform test -var run_id=demo   # run_id becomes part of the bucket name
```

The bucket name contains `run_id`, `local` by default; CI sets `TF_VAR_run_id` to the workflow run id. A variable in the test file would override `TF_VAR_*`, so the default lives in the helper module instead.

## Test account setup

`terraform/tests/integration/account_setup` is a small root configuration applied once per test AWS account by someone with IAM rights there. It creates:

| Resource | Why |
|---|---|
| IAM role `braintf-tftest-ci` | The integration job assumes it through the account's GitHub OIDC provider. Trust: audience `sts.amazonaws.com`, `sub` limited to pull requests and `main` pushes of `vcs_project_path` (both claim formats, as in main_module), or the list in `github_oidc_subjects`. Permissions: `s3:*` only on `braintf-tftest-*` buckets, `s3:ListAllMyBuckets`, use of the fixture key, `kms:ListAliases`. No access to the state bucket or to BrainTF's own resources |
| KMS key `alias/braintf-tftest` | Encrypts test buckets. Long-lived, because a deleted key stays pending deletion for at least 7 days |
| GitHub Actions variables `TF_TEST_ROLE_ARN`, `TF_TEST_AWS_REGION` | What the workflow reads. Variables, not secrets: neither value is secret, and with OIDC no AWS keys are stored in GitHub. Written through the GitHub provider, the same way main_module writes `OIDC_ROLE_ARN` |

Prerequisites: the account already has the GitHub OIDC provider (main_module creates it), and the GitHub token can write Actions variables of the repository.

It needs two variables with the same names and values main_module uses: `vcs_project_path` and `vcs_token`. Either put them in `terraform.tfvars` and `secrets.auto.tfvars` in this folder (both are git-ignored), or pass main_module's files:

```bash
cd terraform/tests/integration/account_setup
terraform init
terraform plan -var-file=../../../main_module/terraform.tfvars -var-file=../../../main_module/secrets.auto.tfvars   # then apply
```

With main_module's files Terraform warns about their other values ("Value for undeclared variable"); that is expected.

State is local; for a shared test account move it to the S3 backend. `terraform destroy` removes the role, schedules the key for deletion and deletes the two variables; destroy it before main_module, because it looks up main_module's OIDC provider.

For a public repository or a paid GitHub plan, a GitHub environment with required reviewers gives a stronger gate: add `environment: terraform-test` to the integration job and set `github_oidc_subjects = ["repo:<owner>/<repo>:environment:terraform-test"]`, so only approved runs can assume the role.

## Test catalogue

Runs whose name starts with `finding_` describe an open finding and fail on purpose; see [Open findings](#open-findings).

### `terraform/tests/unit/bootstrap.tftest.hcl`

Mocked `aws` and `local` providers; the upstream KMS and S3 modules are overridden, so the tests look only at bootstrap's own resources and locals.

| Run | Checks |
|---|---|
| `state_bucket_name_is_lowercase_and_regional` | `local.state_bucket` is `<prefix>-<repo in lowercase>-<region>` |
| `state_bucket_name_replaces_underscores_and_uses_custom_prefix` | `_` becomes `-`, and `platform_state_bucket_prefix` replaces the default prefix |
| `backend_file_is_generated_for_main_module` | `backend.generated.tf` is planned next to `main_module` with the state bucket, key `main-module/terraform.tfstate`, region, `encrypt` and `use_lockfile` |
| `tfvars_are_copied_to_main_module` | `terraform.tfvars` is copied byte for byte to `main_module/terraform.auto.tfvars` |
| `state_bucket_denies_insecure_transport` | The state bucket policy starts with a Deny of non-TLS requests to the bucket and its objects (`apply` with mocks, because the policy needs the bucket ARN) |
| `finding_state_bucket_name_keeps_only_s3_characters` | Open finding 1 |
| `finding_repo_name_too_long_for_bucket_is_rejected` | Open finding 2 |

### `terraform/tests/unit/main_module.tftest.hcl`

Mocked `aws`, `random`, `github`, `gitlab`; modules `oidc` and `ai_lambda` are overridden.

| Run | Checks |
|---|---|
| `ai_handler_disabled_creates_only_vcs_integration` | With `ai_handler_create = false`: no artifacts bucket, OIDC, IAM, DynamoDB, Lambda, webhook secret or SSM parameters; only the GitHub integration; no AI handler CI variables |
| `ai_handler_enabled_creates_ai_stack` | With the AI handler on: every component is planned, all AI handler CI variables are published, exactly three SSM parameters, all `SecureString` |
| `shared_resource_names_follow_convention` | Names other components depend on: the artifacts bucket, the state bucket (bootstrap computes the same name separately) and the SSM parameters (the Lambdas read them by name) |
| `only_job_token_is_secret` | `JOB_TOKEN` is the only CI value stored as a secret |
| `ci_variables_point_to_this_deployment` | `ARTIFACTS_BUCKET` points to `<bucket>/logs`, `OIDC_ROLE_ARN` comes from the oidc module, `VCS_API_ENDPOINT` is `https://api.<host>`, `OIDC_AUDIENCE` is `sts.amazonaws.com`, `AWS_REGION` is the deployment region |
| `backend_params_use_bootstrap_bucket_by_default` | `TERRAFORM_BACKEND_PARAMS` with the bootstrap state bucket, the managed key, region, KMS alias, encryption and S3 locking |
| `backend_params_use_managed_bucket_when_set` | `managed_state_bucket` and `managed_state_key` replace the defaults |
| `github_oidc_trust_limited_to_main_and_pull_requests` | The OIDC `sub` values allow only `main` pushes and pull requests of the repository, in both claim formats |
| `gitlab_uses_gitlab_integration_and_claims` | With `vcs_provider = gitlab`: only the GitLab integration, GitLab `sub` claim and audience, API endpoint `https://<host>/api/v4` |
| `rejects_unknown_vcs_provider` | Validation of `vcs_provider` |
| `rejects_unknown_log_level` | Validation of `log_level` |
| `rejects_temperature_above_two` | Validation of `ai_temperature` |
| `rejects_state_key_without_directory` | Validation of `managed_state_key`: a directory prefix is required |
| `rejects_state_key_with_leading_slash` | Validation of `managed_state_key`: no leading slash |
| `finding_artifacts_bucket_name_keeps_only_s3_characters` | Open finding 1 |
| `finding_repo_name_too_long_is_rejected` | Open finding 2 |

### `terraform/tests/integration/bucket.tftest.hcl`

Real AWS in the test account; see [Integration tests](#integration-tests).

| Run | Checks |
|---|---|
| `setup` | Unique bucket name and the fixture KMS key |
| `create_bucket` | AWS creates the bucket under the requested name and accepts the lifecycle rule |
| `tls_only_policy_is_attached_in_aws` | The TLS-only bucket policy is attached in S3 |
| `finding_placeholder_objects_use_bucket_kms_key_and_versioning` | Open finding 3 |

## Open findings

These runs describe what the code should do and fail today. They stay red until the code is fixed; the fix is out of scope of this change. When a finding is fixed, the run turns green and can be renamed without the `finding_` prefix.

| # | Finding | Where in the code | Failing runs | What the run shows |
|---|---|---|---|---|
| 1 | Bucket name sanitising does nothing: `replace(…, "[^a-z0-9.-]", "")` matches that text literally; a regular expression needs slashes, `"/[^a-z0-9.-]/"` | `bootstrap/main.tf` (`local.state_bucket`), `main_module/main.tf` (`local.artifacts_bucket`, `local.bootstrap_state_bucket`) | `finding_state_bucket_name_keeps_only_s3_characters`, `finding_artifacts_bucket_name_keeps_only_s3_characters` | `backend-state-bucket-brain+tf-eu-west-1`, `artifacts-brain/tf-eu-west-1` |
| 2 | `vcs_repo_name` has no validation. The safe length depends on the prefixes and the region: in `eu-west-1` with the default prefixes, more than 28 characters break the Lambda IAM role name (`Terraform-AI-Handler-Role-<repo>-<region>`, limit 64) and more than 32 the state bucket name (limit 63). Characters such as space or `+` break IAM, KMS alias or S3 names. The user only learns it from the AWS provider | `bootstrap/variables.tf`, `main_module/variables.tf` | `finding_repo_name_too_long_for_bucket_is_rejected`, `finding_repo_name_too_long_is_rejected` | `var.vcs_repo_name, was expected to report an error but did not` |
| 3 | The directory placeholder objects only reference the bucket id, which is known as soon as the bucket exists, before the upstream module applies default encryption and versioning. `logs/` and `artifacts/` end up with SSE-S3 (`AES256`) instead of the KMS key, and often without a version id. The lifecycle configuration references `var.bucket_name` and does not depend on the bucket at all. Only an integration test can show it, because it is about the order of AWS calls; the same `AES256` objects are visible in a deployed artifacts bucket | `modules/bucket/main.tf` (`aws_s3_object.directory`, `aws_s3_bucket_lifecycle_configuration.lifecycle`) | `finding_placeholder_objects_use_bucket_kms_key_and_versioning` (integration) | `"server_side_encryption": "AES256"`, `"version_id": "null"` |

## Prerequisites and constraints

| Topic | Requirement |
|---|---|
| Terraform version | The tests need Terraform 1.14 or newer (`terraform/tests/unit/versions.tf`); the pipeline uses `TERRAFORM_VERSION` 1.14.8, the same as `pipeline.yml` (see `DEPENDENCIES.md`). Checked: 1.14.0 and 1.14.8 give the same results; 1.12.0 crashes inside `terraform test`; on 1.11.0 the mocked AWS provider returns the write-only `value_wo` of the SSM parameters, which Terraform rejects as an invalid plan. `main_module` itself requires 1.11+. `skip_cleanup` and `terraform test cleanup` exist only in experimental builds of 1.14.8; unit tests do not need them |
| Providers | `init` downloads every provider even for mocked tests, because mocks need the provider schema. `.terraform.lock.hcl` is not committed, so provider versions float within their constraints; a new provider release can change mock behaviour |
| Modules | `main_module` pulls pinned `terraform-aws-modules` from GitHub; an uncached `init` took 2 min 43 s. The pipeline caches the plugin cache and `.terraform/modules` |
| Backend | Not used: the test directories have no backend, state lives in memory. `backend.generated.tf` in main_module only causes a "Backend configuration ignored" warning |
| Test data | In the test files and in `terraform/tests/mocks`: fake account id `123456789012`, region `eu-west-1`, fake ARNs and IDs |
| AWS credentials | Unit tests: none, and no network. Integration tests: the OIDC role from `terraform/tests/integration/account_setup`; no AWS keys are stored in GitHub |
| Resource isolation | Integration tests run in a test account, with names unique per run (`braintf-tftest-<run_id>-<index>-<random>`) and a role that cannot touch anything else. Unit tests create nothing |
| Cleanup | `terraform test` destroys in reverse `run` order at the end of the file, buckets use `force_destroy`, and the leak check fails the job if a bucket with the run's prefix is left. The KMS key is a long-lived fixture |

## Known risks and limitations

- **Mocks are not AWS.** A green unit test does not mean AWS accepts the change (finding 3 is an example). Integration tests and a full deployment to a test account cover that gap.
- **Mocks need upkeep.** New resources and attributes need new overrides or defaults, and upstream modules can break on generated values.
- **Tests execute code.** Provisioners and external scripts run unless overridden; review test files as carefully as the configuration they test. The network cut in the pipeline is the safety net.
- **The sudo fallback for the network namespace.** GitHub's Ubuntu 24.04 runners block unprivileged user namespaces, so the pipeline uses `sudo unshare --net` and drops back to the runner user with `setpriv`. Self-hosted runners without passwordless sudo need another way to cut the network.
- **The JUnit normalizer depends on Terraform's report format.** If a Terraform upgrade changes the format, the report may fall back to "NaNms" or "Encountered an error"; the test results themselves are not affected. Check the report after upgrading Terraform.
- **Slow `init`.** Uncached `init` of `main_module` takes minutes because of git-sourced modules.
- **Red pipeline until the findings are fixed.** The open findings fail on purpose, so the unit job stays red until then, and so does the integration job. Make the jobs required checks only after that.
- **Finding 3 is a race.** In a run where the encryption configuration happens to win, its integration run can pass; it failed in every run so far.
- **Leftovers and cost of integration tests.** A cancelled runner or a failed teardown can leave a test bucket. The leak check reports it; it covers only S3 buckets, so new integration tests must extend it. Keep integration tests to cheap, fast resources.
- **Trust of the test role.** Without a GitHub environment, any workflow run of a pull request in the repository can assume the role. Its permissions are limited to `braintf-tftest-*` resources; an environment with reviewers is the stronger option where available.

## Plan for further implementation

1. **Fix the open findings** in separate pull requests; each fix turns its `finding_` run green.
2. **More unit tests**: `modules/oidc` (trust policy, no `Resource = "*"`), `modules/bucket` (lifecycle rules, bucket policy JSON), `modules/iam` (log group ARNs match the Lambda function names, policy scope), `modules/vcs_integration/github` and `gitlab` (masked values become secrets, webhook only with the AI handler), `modules/lambdas` (environment variables, layer rebuild trigger; plan only), and the branch of `bootstrap` that skips `backend.generated.tf` when `main_module` already has a backend. Then make the unit job a required status check and add a check that every module under `terraform/modules` has a test file in `terraform/tests/unit`.
3. **More integration tests**: `modules/dynamodb` (keys, TTL, SSE on an on-demand table) next; a GitHub environment with required reviewers for the integration job; a nightly run; a sweeper that removes `braintf-tftest-*` resources older than a day; a budget alert on the test account.
4. **End-to-end and versions**: a full `main_module` deployment in an ephemeral environment before releases; re-evaluate newer Terraform versions for `skip_cleanup` and backend blocks in `run` blocks; consider committing `.terraform.lock.hcl`.

## What we took from the HashiCorp tutorial

The primary reference is [Write Terraform tests](https://developer.hashicorp.com/terraform/tutorials/configuration-language/test).

Adopted:

- `.tftest.hcl` files in a `tests` directory, here one shared `terraform/tests` with `unit` and `integration`, and `run` blocks that name the module they test.
- `run` blocks with `command = plan`, `assert` blocks with clear error messages, `expect_failures` for validation rules.
- Mocks and overrides (`mock_provider`, `override_resource`, `override_data`, `override_module`) instead of real resources in unit tests.
- `command = apply` against real infrastructure with a setup helper module for unique names (like the tutorial's `tests/setup` with `random_pet`), a read-back helper (like the tutorial's `tests/final`), and automatic teardown.
- Pinned provider versions and `terraform init` after adding a provider or module.

Not adopted:

- HCP Terraform and private registry testing (`-cloud-run`, "Enable testing for Module"): BrainTF runs on GitHub Actions with an S3 backend, and its modules are local paths.
- The live HTTP endpoint check: BrainTF has no public website.

Other references: [Tests language](https://developer.hashicorp.com/terraform/language/tests), [Mocks](https://developer.hashicorp.com/terraform/language/tests/mocking), [`terraform test` command](https://developer.hashicorp.com/terraform/cli/commands/test).
