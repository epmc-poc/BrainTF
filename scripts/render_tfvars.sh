#!/usr/bin/env bash
# render_tfvars.sh — (re)generate terraform/main_module/terraform.auto.tfvars for
# a BrainTF instance repository, plus secrets.auto.tfvars when token env vars are set.
#
# Auto-detected (each can be overridden by the same-named env var):
#   VCS_HOSTNAME, VCS_PROJECT_PATH  <- git remote (origin, else first remote)
#   VCS_REPO_NAME                   <- repository name from the remote URL
#   VCS_PROVIDER                    <- gitlab when the host contains "gitlab", else github
#   INSTANCE_ID                     <- repo name 'braintf-<id>' -> '<id>'
#   OWNER_MAIL                      <- AWS caller ARN user name when it looks like
#                                      an e-mail (IAM user / SSO session name@epam.com)
#   OIDC_PROVIDER                   <- token.actions.githubusercontent.com or gitlab.com
#
# Environment-specific values (subnet IDs, security groups, AI endpoint, ...)
# keep the repository defaults and may be overridden via env or edited afterwards:
#   ENVIRONMENT TEAM DEPLOYED_BY STATE_BUCKET_PREFIX ARTIFACTS_BUCKET_PREFIX
#   PRIVATE_SUBNET_IDS SECURITY_GROUPS  (raw HCL list strings)
#   AI_HANDLER_CREATE RAG_ENABLE AI_API_BASE_URL LLM_MODEL AI_TEMPERATURE LOG_LEVEL
#   RUN_*  (per-stage flags; RUN_ALL sets all seven at once)
#
# Secrets: when VCS_TOKEN / AI_TOKEN / JOB_TOKEN are set in the environment,
# secrets.auto.tfvars is rewritten with them; otherwise it is left untouched.
#
# Usage:
#   ./scripts/render_tfvars.sh
#   INSTANCE_ID=smoke VCS_PROJECT_PATH=vasjr99/braintf-smoke ./scripts/render_tfvars.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform/main_module/terraform.auto.tfvars"
SECRETS_TFVARS="${REPO_ROOT}/terraform/main_module/secrets.auto.tfvars"

die() { echo "render_tfvars: error: $*" >&2; exit 1; }

# --- Detect VCS coordinates from the git remote -----------------------------
remote="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
if [[ -z "${remote}" ]]; then
  first_remote="$(git -C "${REPO_ROOT}" remote 2>/dev/null | head -n1 || true)"
  [[ -n "${first_remote}" ]] && remote="$(git -C "${REPO_ROOT}" remote get-url "${first_remote}" 2>/dev/null || true)"
fi
[[ -n "${remote}" ]] || die "no git remote found — set VCS_HOSTNAME and VCS_PROJECT_PATH explicitly"

remote="${remote%.git}"
if [[ "${remote}" =~ ^git@([^:]+):(.+)$ ]]; then
  det_host="${BASH_REMATCH[1]}"; det_path="${BASH_REMATCH[2]}"
elif [[ "${remote}" =~ ^https?://([^/]+)/(.+)$ ]]; then
  det_host="${BASH_REMATCH[1]}"; det_path="${BASH_REMATCH[2]}"
else
  die "cannot parse remote URL '${remote}'"
fi

det_repo="${det_path##*/}"
det_instance=""
[[ "${det_repo}" =~ ^braintf-(.+)$ ]] && det_instance="${BASH_REMATCH[1]}"

# --- Detect owner e-mail + account id from the AWS caller identity -----------
det_owner=""
det_account=""
if command -v aws >/dev/null 2>&1; then
  arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"
  caller="${arn##*/}"
  if [[ "${caller}" == *@* ]]; then
    det_owner="$(printf '%s' "${caller}" | tr '[:upper:]' '[:lower:]')"
  fi
  det_account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
fi
det_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "${det_region}" ]] && command -v aws >/dev/null 2>&1; then
  det_region="$(aws configure get region 2>/dev/null || true)"
fi

# --- Resolve final values (env var wins over detection) ----------------------
if [[ -z "${VCS_PROVIDER:-}" ]]; then
  [[ "${det_host}" == *gitlab* ]] && VCS_PROVIDER="gitlab" || VCS_PROVIDER="github"
fi
VCS_HOSTNAME="${VCS_HOSTNAME:-${det_host}}"
VCS_PROJECT_PATH="${VCS_PROJECT_PATH:-${det_path}}"
VCS_REPO_NAME="${VCS_REPO_NAME:-${det_repo}}"
INSTANCE_ID="${INSTANCE_ID:-${det_instance}}"
OWNER_MAIL="${OWNER_MAIL:-${det_owner}}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-${det_account}}"
AWS_REGION="${AWS_REGION:-${det_region}}"
if [[ -z "${OIDC_PROVIDER:-}" ]]; then
  [[ "${VCS_PROVIDER}" == "gitlab" ]] && OIDC_PROVIDER="gitlab.com" \
    || OIDC_PROVIDER="token.actions.githubusercontent.com"
fi

[[ -n "${INSTANCE_ID}" ]] || die "cannot derive instance_id from repo name '${det_repo}' (expected 'braintf-<id>') — set INSTANCE_ID"
[[ "${INSTANCE_ID}" =~ ^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$ ]] \
  || die "instance_id '${INSTANCE_ID}' is invalid (lowercase alphanumeric with hyphens, 1-30 chars)"

# Environment-specific defaults (match docs/config_files + sandbox defaults).
ENVIRONMENT="${ENVIRONMENT:-Dev}"
TEAM="${TEAM:-DevOps}"
DEPLOYED_BY="${DEPLOYED_BY:-Terraform}"
STATE_BUCKET_PREFIX="${STATE_BUCKET_PREFIX:-braintf-state}"
MANAGED_STATE_BUCKET="${MANAGED_STATE_BUCKET:-}"
MANAGED_STATE_KEY="${MANAGED_STATE_KEY:-}"
ARTIFACTS_BUCKET_PREFIX="${ARTIFACTS_BUCKET_PREFIX:-ai-handler-artifacts-bucket}"
ARTIFACTS_PATH="${ARTIFACTS_PATH:-artifacts}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
AI_HANDLER_CREATE="${AI_HANDLER_CREATE:-true}"
RAG_ENABLE="${RAG_ENABLE:-true}"
AI_API_BASE_URL="${AI_API_BASE_URL:-https://ai-proxy.lab.epam.com/openai/deployments/gpt-4o}"
LLM_MODEL="${LLM_MODEL:-gpt-4o}"
AI_TEMPERATURE="${AI_TEMPERATURE:-0.1}"
PRIVATE_SUBNET_IDS="${PRIVATE_SUBNET_IDS:-[\"subnet-0a786857b4f846c8b\", \"subnet-02e98b506f99b05fd\", \"subnet-046f6f6046f26aed3\"]}"
SECURITY_GROUPS="${SECURITY_GROUPS:-[\"sg-07b02162c43cd1b3d\"]}"

RUN_ALL="${RUN_ALL:-true}"
RUN_TFLINT_ANALYSIS="${RUN_TFLINT_ANALYSIS:-${RUN_ALL}}"
RUN_TERRAFORM_VALIDATE="${RUN_TERRAFORM_VALIDATE:-${RUN_ALL}}"
RUN_CHECKOV_ANALYSIS="${RUN_CHECKOV_ANALYSIS:-${RUN_ALL}}"
RUN_TFSEC_ANALYSIS="${RUN_TFSEC_ANALYSIS:-${RUN_ALL}}"
RUN_TRIVY_ANALYSIS="${RUN_TRIVY_ANALYSIS:-${RUN_ALL}}"
RUN_TERRAFORM_PLAN="${RUN_TERRAFORM_PLAN:-${RUN_ALL}}"
RUN_TERRAFORM_APPLY="${RUN_TERRAFORM_APPLY:-${RUN_ALL}}"

# --- Render terraform.auto.tfvars --------------------------------------------
cat > "${TFVARS}" <<EOF
# Generated by scripts/render_tfvars.sh — do not edit derived values by hand,
# re-run the script or pass overrides via environment variables.
# This file is gitignored: it is per-instance, per-environment.

# Tag block
environment = "${ENVIRONMENT}"
team        = "${TEAM}"
deployed_by = "${DEPLOYED_BY}"
owner_mail  = "${OWNER_MAIL}"

# Block of common variables
vcs_repo_name = "${VCS_REPO_NAME}"

# State backend configuration
state_bucket_prefix = "${STATE_BUCKET_PREFIX}"

# Instance identifier (immutable after first apply)
instance_id = "${INSTANCE_ID}"

# Block of VCS variables
vcs_provider     = "${VCS_PROVIDER}"
vcs_hostname     = "${VCS_HOSTNAME}"
vcs_project_path = "${VCS_PROJECT_PATH}"

# The Pipeline Stages Activation Block
run_tflint_analysis    = "${RUN_TFLINT_ANALYSIS}"
run_terraform_validate = "${RUN_TERRAFORM_VALIDATE}"
run_checkov_analysis   = "${RUN_CHECKOV_ANALYSIS}"
run_tfsec_analysis     = "${RUN_TFSEC_ANALYSIS}"
run_trivy_analysis     = "${RUN_TRIVY_ANALYSIS}"
run_terraform_plan     = "${RUN_TERRAFORM_PLAN}"
run_terraform_apply    = "${RUN_TERRAFORM_APPLY}"

# Managed workload state backend configuration (code under WORK_DIRS)
managed_state_bucket = "${MANAGED_STATE_BUCKET}"
managed_state_key    = "${MANAGED_STATE_KEY}"

# AI Handler block
ai_handler_create       = "${AI_HANDLER_CREATE}"
rag_enable              = "${RAG_ENABLE}"
artifacts_path          = "${ARTIFACTS_PATH}"
log_level               = "${LOG_LEVEL}"
ai_api_base_url         = "${AI_API_BASE_URL}"
llm_model               = "${LLM_MODEL}"
ai_temperature          = ${AI_TEMPERATURE}
oidc_provider           = "${OIDC_PROVIDER}"
artifacts_bucket_prefix = "${ARTIFACTS_BUCKET_PREFIX}"
private_subnet_ids      = ${PRIVATE_SUBNET_IDS}
security_groups         = ${SECURITY_GROUPS}
EOF

command -v terraform >/dev/null 2>&1 && terraform fmt "${TFVARS}" >/dev/null

# --- Render secrets.auto.tfvars (only when tokens are provided) ---------------
if [[ -n "${VCS_TOKEN:-}${AI_TOKEN:-}${JOB_TOKEN:-}" ]]; then
  cat > "${SECRETS_TFVARS}" <<EOF
# Generated by scripts/render_tfvars.sh — do not commit.
job_token = "${JOB_TOKEN:-}"
vcs_token = "${VCS_TOKEN:-}"
ai_token  = "${AI_TOKEN:-}"
EOF
  echo "wrote ${SECRETS_TFVARS}"
else
  echo "VCS_TOKEN/AI_TOKEN/JOB_TOKEN not set — leaving secrets.auto.tfvars untouched"
fi

# --- Render backend.tf (full S3 backend config -> plain 'terraform init') ------
BACKEND_TF="${REPO_ROOT}/terraform/main_module/backend.tf"
if [[ -n "${AWS_ACCOUNT_ID}" && -n "${AWS_REGION}" ]]; then
  cat > "${BACKEND_TF}" <<EOF
# ======================= Terraform state backend =======================
# Generated by scripts/render_tfvars.sh — per-instance values, no credentials.
# Commit this file in the instance repository; the template keeps a partial
# backend "s3" {} block instead. With this file, plain 'terraform init' works.
terraform {
  backend "s3" {
    bucket       = "${STATE_BUCKET_PREFIX}-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    key          = "${INSTANCE_ID}/main-module/terraform.tfstate"
    region       = "${AWS_REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
  command -v terraform >/dev/null 2>&1 && terraform fmt "${BACKEND_TF}" >/dev/null
  echo "wrote ${BACKEND_TF} (full backend config — 'terraform init' needs no flags)"
else
  cat <<'EOF'
AWS_ACCOUNT_ID/AWS_REGION not resolved — backend.tf left as partial config;
run init with:
  terraform init \
    -backend-config="bucket=<state_bucket_prefix>-<account_id>-<region>" \
    -backend-config="key=<instance_id>/main-module/terraform.tfstate" \
    -backend-config="region=<region>" \
    -backend-config="encrypt=true" \
    -backend-config="use_lockfile=true"
EOF
fi

cat <<EOF

wrote ${TFVARS}
  instance_id      = ${INSTANCE_ID}
  vcs_project_path = ${VCS_PROJECT_PATH}   (${VCS_PROVIDER} @ ${VCS_HOSTNAME})
  owner_mail       = ${OWNER_MAIL:-<empty — will fall back to AWS caller ARN in Terraform>}
EOF
