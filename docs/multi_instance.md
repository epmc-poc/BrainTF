# Multi-Instance Deployment — Research & Solution Design

> **Status:** Research deliverable for the "multiple independent BrainTF instances in one
> AWS account" task. No production implementation is included; this document defines the
> necessary and sufficient conditions, the target architecture, and a prioritized plan.

## 1. Problem Statement

BrainTF must support deployment of **multiple independent instances within one AWS
account**, including the case where target applications use the **same VCS provider** and
the **same repository name**. Today almost every resource name is derived from:

```
f(vcs_repo_name, region [, vcs_provider])
```

Because `vcs_repo_name` is effectively the repository name, two instances with the same
repository name, same VCS type, same account and same region collide on nearly every
resource, configuration value, state file, secret, VCS variable, and webhook.

Instances must remain independently deployable, configurable, and removable.

### Selected deployment context (stakeholder decisions)

| Decision point | Chosen approach |
|---|---|
| AWS account | **Single shared account**; isolation via `instance_id` |
| Instance identity | Mandatory immutable `instance_id` (value = owner/env, e.g. `vasjr`) |
| Per-developer repository | **Template repository** created in org **`epmc-poc`**, named `braintf-{instance_id}` |
| Repository provisioning | **GitHub Actions "factory"** (`workflow_dispatch`) in upstream `epmc-poc/BrainTF` |
| AWS provisioning | Runs **from the newly created template repo's own pipeline** (bootstrap → main_module) |
| OIDC provider | **Shared**, created once via a dedicated `terraform/shared/` module |
| Terraform state | **Model A** — one state bucket per instance |
| IAM scope | Tightened to per-instance DynamoDB / SSM / S3 / KMS ARNs |
| Existing live instance (account `123408385862`) | **Left as-is**; new model applies to new instances |
| Upstream sync | `scripts/sync-upstream.sh` shipped in the template |

---

## 2. Collision Inventory (Acceptance Criteria #1)

### 2.1 Bootstrap (`terraform/bootstrap/main.tf`)

| Resource | Name formula | Collision on 2nd instance |
|---|---|---|
| S3 state bucket | `{platform_state_bucket_prefix}-{vcs_repo_name}-{region}` (main.tf:9) | Hard fail — S3 names globally unique |
| KMS alias | `alias/kms_key_{vcs_repo_name}_{region}` (main.tf:75) | `AlreadyExistsException` (unique per account/region) |
| IAM role | `Terraform-role-{vcs_repo_name}-{region}` (main.tf:165) | Fail — role names unique per account |
| IAM inline policy | `Terraform-State-Access-{vcs_repo_name}-{region}` (main.tf:183) | Fail with the role |
| `local_file.backend_config` | Fixed path `main_module/backend.generated.tf`, key `main-module/terraform.tfstate` (main.tf:22-46) | **Silently overwrites** backend file; identical key → shared `main_module` state |
| `local_file.this` | Fixed path `main_module/terraform.auto.tfvars` (main.tf:53-56) | Silently overwrites generated tfvars |
| Bootstrap state | Local `terraform.tfstate` in `terraform/bootstrap/` | One checkout = one file → no place for a second instance |

### 2.2 Main module (`terraform/main_module/main.tf`, locals 29-44)

| Resource | Name formula | Collision type |
|---|---|---|
| `data.aws_kms_alias` | `alias/kms_key_{vcs_repo_name}_{region}` (main.tf:20) | Resolves to **another** instance's key → shared KMS |
| OIDC role / policy | `{vcs_repo_name}-oidc-{vcs_provider}-{region}-role` / `-policy` (main.tf:35-36) | Fail — unique per account |
| **OIDC provider** | `aws_iam_openid_connect_provider` for `https://{oidc_provider}` (oidc/main.tf:7) | **One provider per issuer URL per account** → apply fails; destroying one deletes it for all |
| Artifacts bucket | `{artifacts_bucket_prefix}-{vcs_repo_name}-{region}` (main.tf:37) | Hard fail — global S3 uniqueness |
| DynamoDB table | `ai-chat-history-{vcs_repo_name}-{region}` (main.tf:38) | Fail — unique per account/region |
| Lambda ×2 | `AI_Handler_TF_Errors_{vcs_repo_name}`, `AI_Handler_Comment_{vcs_repo_name}` (lambdas/main.tf:83,140) — **no region** | Fail in same region |
| Lambda layer | `layer-{vcs_repo_name}-{region}` (main.tf:341) | Fail |
| Lambda IAM role/policy | `Terraform-AI-Handler-Role/Policy-{vcs_repo_name}-{region}` (iam/main.tf:14,125) | Fail |
| CloudWatch log groups | `/aws/lambda/AI_Handler_*_{vcs_repo_name}` (iam/main.tf:27-28) | Fail / log sharing |
| SSM parameters | `/{vcs_repo_name}/webhook_secret`, `/ai_token`, `/vcs_token` (main.tf:39-41) | **Silently overwritten** — cross-instance token leakage |
| Managed workload state key | default `pipeline/terraform.tfstate` (variables.tf:109) | Shared tfstate → corruption |

### 2.3 VCS integration (outside AWS)

- GitHub (`vcs_integration/github/main.tf`) / GitLab (`.../gitlab/main.tf`) write
  **repository-level** variables/secrets (`ARTIFACTS_BUCKET`, `OIDC_ROLE_ARN`,
  `OIDC_AUDIENCE`, `VCS_API_ENDPOINT`, `JOB_TOKEN`, `RUN_*`, `TERRAFORM_BACKEND_PARAMS` —
  main.tf:74-191). Two instances on the same repo → second apply overwrites them.
- **Webhooks:** multiple hooks per repo are allowed → both instances receive every
  `issue_comment`/note event → duplicate bot responses.
- **OIDC `sub`:** `repo:{vcs_project_path}:...` identical for both → only one
  `OIDC_ROLE_ARN` repo variable can win.

### 2.4 Cross-region note

IAM is global. Even with **different regions**, the OIDC provider (one per issuer URL per
account) and all VCS-level items still collide. Region in the name protects
S3/KMS/DynamoDB/Lambda/log-groups only.

### 2.5 Pre-existing IAM over-permission

- `modules/iam`: Lambda policy grants `dynamodb:*` on `table/*` and `ssm:Get*` on
  `parameter/*` → an instance can read another's tables and **secrets**.
- `modules/oidc`: grants whole managed-state bucket (`bucket/*`) → cross-instance state
  access under a shared bucket.

---

## 3. Mandatory Instance Identifier (AC #2)

A **mandatory**, immutable-by-convention input, independent of the repository name.

```hcl
variable "instance_id" {
  description = "Immutable, account-unique identifier for this BrainTF instance. Independent of the repository name; namespaces all instance-scoped AWS resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.instance_id))
    error_message = "instance_id must be lowercase alphanumeric with hyphens, 1-30 chars, not starting/ending with a hyphen."
  }
}
```

- **30-char cap** keeps derived names within AWS limits (S3 ≤63, Lambda ≤64).
- **Immutability:** not enforceable by Terraform; enforced by convention + docs. Changing
  `instance_id` = destroy + recreate of all resources and state relocation → treat as a
  new instance.
- **Uniqueness:** account-unique; maintain a lightweight registry (see §9) to avoid
  duplicate ids.
- **Ownership:** encode owner in `OwnerEmail` tag (existing) and optionally in
  `instance_id`.
- `vcs_repo_name` is demoted to the `Project` tag + VCS metadata only.

---

## 4. Naming Convention for Instance-Scoped Resources (AC #3)

| Resource | Proposed name |
|---|---|
| State S3 bucket | `{platform_state_bucket_prefix}-{instance_id}-{region}` |
| Artifacts S3 bucket | `{artifacts_bucket_prefix}-{instance_id}-{region}` |
| KMS alias | `alias/btf-{instance_id}-{region}` |
| Terraform IAM role / policy | `Terraform-role-{instance_id}-{region}` / `Terraform-State-Access-{instance_id}-{region}` |
| OIDC IAM role / policy | `{instance_id}-oidc-{vcs_provider}-role` / `-policy` |
| Lambda exec role / policy | `Terraform-AI-Handler-Role-{instance_id}-{region}` / `-Policy-...` |
| Lambda functions | `AI_Handler_TF_Errors_{instance_id}`, `AI_Handler_Comment_{instance_id}` |
| Lambda layer | `layer-{instance_id}-{region}` |
| CloudWatch log groups | `/aws/lambda/AI_Handler_*_{instance_id}` |
| DynamoDB table | `ai-chat-history-{instance_id}-{region}` |
| SSM parameters | `/{instance_id}/vcs_token`, `/{instance_id}/ai_token`, `/{instance_id}/webhook_secret` |
| State keys | `bootstrap/terraform.tfstate`, `main-module/terraform.tfstate`, `pipeline/terraform.tfstate` (inside the per-instance bucket) |

Add a mandatory default tag `InstanceId = var.instance_id` in both root modules
(`versions.tf` provider `default_tags`). Apply `lower()` consistently (KMS alias and IAM
names currently use the raw value and will mismatch the lowercased bucket name otherwise).

---

## 5. Target Architecture

### 5.1 Three-layer provisioning model

```
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 0 — Account shared (applied ONCE per account)                    │
│   terraform/shared/                                                     │
│     • IAM OIDC provider(s): token.actions.githubusercontent.com / ...  │
│     • "bootstrap admin" role trusted by the OIDC provider (optional)   │
└──────────────────────────────────────────────────────────────────────┘
                                   │
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 1 — Instance Factory (GitHub Actions in epmc-poc/BrainTF)        │
│   .github/workflows/create-instance.yml  (workflow_dispatch)           │
│     input: instance_id                                                  │
│     1. Create repo epmc-poc/braintf-{instance_id} FROM TEMPLATE         │
│     2. Run scripts/gen-tfvars.sh → instance.auto.tfvars                 │
│     3. Commit/seed config into the new repo                             │
│     (no AWS actions here — avoids the OIDC chicken-and-egg)             │
└──────────────────────────────────────────────────────────────────────┘
                                   │
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 2 — AWS deploy (runs FROM epmc-poc/braintf-{instance_id})        │
│   the new repo's own pipeline:                                          │
│     bootstrap  → state bucket + KMS + Terraform role (per instance_id)  │
│     main_module→ artifacts, SSM, OIDC role (→ shared provider),         │
│                  Lambda + layer, DynamoDB, VCS vars/secrets/webhook     │
│   authenticates via the shared OIDC provider + bootstrap admin role     │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 Per-instance resource layout (example)

```
AWS account (shared)
├── Shared (once)
│   └── IAM OIDC provider: token.actions.githubusercontent.com
├── Instance "vasjr"  (repo: epmc-poc/braintf-vasjr)
│   ├── S3 backend-state-bucket-vasjr-{region}  (keys: bootstrap/, main-module/, pipeline/)
│   ├── KMS alias/btf-vasjr-{region}
│   ├── IAM Terraform-role-vasjr-{region}, vasjr-oidc-github-role (→ shared provider)
│   ├── SSM /vasjr/*, DynamoDB ai-chat-history-vasjr-{region}
│   ├── Lambda AI_Handler_*_vasjr + layer-vasjr-{region}
│   └── VCS: variables/secrets/webhook on epmc-poc/braintf-vasjr
├── Instance "oleg"  (repo: epmc-poc/braintf-oleg)   — same layout
└── Instance "igor"  (repo: epmc-poc/braintf-igor)   — same layout
```

### 5.3 Why template (not fork)

| | Fork | Template (chosen) |
|---|---|---|
| Terraform-native resource | No (`gh`/API only) | **Yes** (`github_repository` with `template {}`) |
| Count limit | 1 per account/org | **Unlimited** |
| Link to upstream | Shared network / PRs to upstream | **Independent** repo |
| Upstream sync | Button / `gh repo sync` | Manual via `scripts/sync-upstream.sh` |

A fork cannot be used here because org `epmc-poc` can hold only **one** fork of
`epmc-poc/BrainTF`; template repos have no such limit. The `epmc-poc/BrainTF` repository
must be flagged `is_template = true` once.

---

## 6. Repository Provisioning Details

### 6.1 Factory workflow (`.github/workflows/create-instance.yml`)

```yaml
on:
  workflow_dispatch:
    inputs:
      instance_id:
        description: "Instance id (e.g. vasjr)"
        required: true
```

Steps: create `epmc-poc/braintf-{instance_id}` from template → run `gen-tfvars.sh` →
seed `instance.auto.tfvars` into the new repo. **No AWS calls** in this layer.

### 6.2 Template repository resource

```hcl
resource "github_repository" "instance" {
  name       = "braintf-${var.instance_id}"
  visibility = "private"
  template {
    owner      = "epmc-poc"
    repository = "BrainTF"
  }
  lifecycle {
    prevent_destroy = true   # never delete a developer's code by accident
  }
}
```

Keep repo creation in a **separate** provisioner module, decoupled from bootstrap, so a
`terraform destroy` of AWS resources can never delete the repository.

### 6.3 Config generation (single source of truth)

`scripts/gen-tfvars.sh` renders a **separate** `instance.auto.tfvars` (never the
upstream-tracked `terraform.tfvars`), so upstream sync does not conflict:

```bash
#!/usr/bin/env bash
set -euo pipefail
INSTANCE_ID="$1"
cat > terraform/main_module/instance.auto.tfvars <<EOF
instance_id      = "${INSTANCE_ID}"
vcs_repo_name    = "braintf-${INSTANCE_ID}"
vcs_project_path = "epmc-poc/braintf-${INSTANCE_ID}"
vcs_provider     = "github"
vcs_hostname     = "github.com"
EOF
```

The same script runs both locally and inside the factory workflow (DRY).

### 6.4 Permissions

- Creating repos in `epmc-poc` requires a token with org repo-creation rights (GitHub App
  or org-owner PAT), stored as an Actions secret on `epmc-poc/BrainTF`.
- The token must have admin on the created repo so the AWS layer can manage
  variables/secrets/webhook (satisfied when the same token created the repo).

### 6.5 Upstream sync (`scripts/sync-upstream.sh`, shipped in template)

```bash
#!/usr/bin/env bash
set -euo pipefail
git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream https://github.com/epmc-poc/BrainTF.git
git fetch upstream
git merge upstream/main --allow-unrelated-histories --no-edit || {
  echo "Resolve conflicts, then: git add . && git commit"; exit 1; }
echo "Synced. Review and push: git push origin main"
```

The first merge needs `--allow-unrelated-histories` (template and upstream have no common
history); subsequent merges are normal. Keeping developer config in `instance.auto.tfvars`
makes code syncs effectively conflict-free.

---

## 7. State Isolation — Model A (AC #4)

- **One state bucket per instance**, name carries `{instance_id}` (§4) → buckets are
  naturally disjoint.
- Keys within each bucket: `bootstrap/terraform.tfstate`,
  `main-module/terraform.tfstate`, `pipeline/terraform.tfstate`.
- **Locking:** native S3 `use_lockfile = true` (already in use); no DynamoDB lock table.
- Bootstrap state (today local, and observed to belong to a different account) moves to
  S3 under `bootstrap/terraform.tfstate`, initialized via `-backend-config` so a single
  checkout can drive the instance deterministically.
- **IAM benefit:** each instance grants only `arn:...:::{its bucket}/*` → no cross-instance
  state access.

Required bootstrap-flow change (AC #8): replace the fixed-path `backend.generated.tf` /
`terraform.auto.tfvars` with per-instance backend config consumed via `-backend-config`,
plus the generated `instance.auto.tfvars` (§6.3).

---

## 8. OIDC & IAM Isolation (AC #5, #7)

### 8.1 Shared OIDC provider

- `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com` (and
  `gitlab.com` if used) lives in `terraform/shared/`, **applied once per account**.
- `main_module` stops creating it and references it via
  `data "aws_iam_openid_connect_provider"` by URL.
- The provider **survives** destruction of any single instance.
- Account `256056996418` already hosts `gitlab.com` / `git.garage.epam.com` providers,
  confirming the shared, pre-existing nature.

### 8.2 Per-instance IAM scoping

- **Lambda policy** (`modules/iam`): DynamoDB → `table/ai-chat-history-{instance_id}-{region}`
  (+ indexes), not `table/*`; SSM → `parameter/{instance_id}/*`, not `parameter/*`.
- **OIDC policy** (`modules/oidc`): S3 scoped to the instance's state/artifacts buckets.
- **KMS:** per-instance key (§4) naturally limits cross-instance decryption.

Result: an instance cannot access another instance's state, secrets, tables, buckets, or
KMS keys unless explicitly intended.

---

## 9. VCS Integration Constraints (AC #6)

With the chosen **one template repo per instance** model (`epmc-poc/braintf-{instance_id}`):

- Repo variables/secrets and the webhook are **repository-scoped** → naturally isolated;
  no last-writer-wins conflict, no duplicate webhook delivery.
- OIDC `sub` binds each instance's role to its own `epmc-poc/braintf-{instance_id}`.
- **No VCS-side redesign required** beyond the `instance_id` AWS work.

**Known limitation (documented, not implemented):** pointing *multiple* instances at a
*single* shared repository remains unsupported — it causes repo-variable conflicts and
duplicate bot responses. If ever needed, it requires GitHub Environments per instance +
per-instance command prefix in the Lambda code (separate task).

`instance_id` uniqueness registry: since all repos live in `epmc-poc`, the set of existing
`braintf-*` repositories is itself the registry; the factory workflow should fail fast if
`braintf-{instance_id}` already exists.

---

## 10. Optional: Per-Developer VPC

VPC is **not** required for isolation — only Lambda ENIs live in a VPC, and
`private_subnet_ids` / `security_groups` are already per-instance inputs (BYO VPC works
today). A per-dev VPC module can be offered later but adds egress cost/design (NAT or VPC
endpoints) and must reach the AI endpoint (`ai-proxy.lab.epam.com`, likely internal). For
a shared account, `instance_id` + an optional per-instance Security Group is the pragmatic
level; a separate AWS account is the right boundary for full IAM/S3-name isolation.

---

## 11. Known Limitations & Risks

- `instance_id` immutability is not technically enforced; renaming = recreate + state move.
- Template repos have no native upstream link; sync is manual (`sync-upstream.sh`).
- Factory workflow holds an org token able to create repos — must be tightly scoped
  (GitHub App preferred) and audited.
- The existing live instance (account `123408385862`) is intentionally left on the old
  naming; it cannot coexist with a second same-repo instance until migrated.
- Cross-region does not remove OIDC-provider or VCS-level collisions.
- Pre-existing over-broad IAM is a security gap even for a single instance.

---

## 12. Prioritized Implementation Plan (high-level)

1. **P0 — `instance_id`:** add the variable to both root modules; thread through every
   resource name (§4); add `InstanceId` default tag; fix lowercase handling.
2. **P0 — Shared OIDC:** create `terraform/shared/` (apply once); switch `main_module` to
   a data source for the provider.
3. **P1 — IAM scoping:** restrict Lambda/OIDC policies to per-instance ARNs (§8.2).
4. **P1 — State isolation (Model A):** per-instance bucket + `{instance_id}` naming; move
   bootstrap state to S3; replace fixed-path generated files with per-instance backend +
   `instance.auto.tfvars` (§7).
5. **P1 — Provisioner:** `github_repository` template module with `prevent_destroy`;
   `scripts/gen-tfvars.sh`; flag `epmc-poc/BrainTF` as a template repo.
6. **P2 — Factory workflow:** `.github/workflows/create-instance.yml` (`workflow_dispatch`)
   that creates the repo and seeds config; AWS deploy runs from the new repo's pipeline.
7. **P2 — Upstream sync:** ship `scripts/sync-upstream.sh` in the template.
8. **P2 — Docs:** update `installation.md`, `state_management.md`; add an onboarding guide
   ("create your instance") and a migration note for the existing instance.

> No production multi-instance implementation is required by this research task.
