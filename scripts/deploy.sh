#!/usr/bin/env bash
# deploy.sh — one-command deploy of a BrainTF instance to an AWS account.
#
# Runs the three steps in the required order:
#   1. terraform/shared       account-level resources (OIDC providers, state bucket,
#                             state KMS). Idempotent; only needs to succeed once per
#                             account + region. Uses local state.
#   2. scripts/render_tfvars  generates terraform/main_module/terraform.auto.tfvars and
#                             backend.tf (needs the state bucket from step 1 to exist).
#   3. terraform/main_module  the instance stack (Lambdas, OIDC role, artifacts, SSM, ...).
#
# Secrets (vcs_token / ai_token / job_token) must reach main_module either via
# terraform/main_module/secrets.auto.tfvars or exported TF_VAR_* (see scripts/tf_env.sh).
#
# If no tokens are exported and there is no secrets.auto.tfvars, deploy.sh sources
# scripts/tf_env.sh to resolve them (SSM / ~/.git-credentials) so main_module does
# not block on interactive "Enter a value:" prompts. Disable with NO_AUTO_SECRETS=1.
#
# Env toggles:
#   BOOTSTRAP=1        apply step 1 — create the account-level shared resources.
#                      Needed ONCE per account+region (bare account), or on the
#                      repo that owns shared management. Without it, step 1 is
#                      always skipped.
#   PLAN_ONLY=1        run 'plan' instead of 'apply' for BOTH shared and
#                      main_module — a true dry run that creates nothing
#   AUTO_APPROVE=1     pass -auto-approve to the main_module apply (non-interactive)
#   INSTANCE_ID=<id>   instance id for tf_env.sh secret lookup (default: tf_env.sh default)
#   NO_AUTO_SECRETS=1  do not auto-source tf_env.sh (provide secrets yourself)
#
# Usage:
#   ./scripts/deploy.sh
#   SKIP_SHARED=1 ./scripts/deploy.sh
#   PLAN_ONLY=1 ./scripts/deploy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_DIR="${REPO_ROOT}/terraform/shared"
MAIN_DIR="${REPO_ROOT}/terraform/main_module"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# --- Step 1: shared (account-level, created ONLY via BOOTSTRAP=1) --------------
# Detects whether shared resources already exist in this account+region:
# the state bucket (<prefix>-<account>-<region>) and an OIDC provider matching
# the repo's VCS host. Returns 0 when both are present.
shared_already_up() {
  command -v aws >/dev/null 2>&1 || return 1
  local account region bucket remote oidc_sub
  account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || return 1
  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
  [[ -n "${region}" ]] || return 1
  bucket="${STATE_BUCKET_PREFIX:-braintf-state}-${account}-${region}"
  aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1 || return 1

  remote="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  case "${remote}" in
    *gitlab*) oidc_sub="gitlab.com" ;;
    *)        oidc_sub="token.actions.githubusercontent.com" ;;
  esac
  aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?contains(Arn, '${oidc_sub}')].Arn" \
    --output text 2>/dev/null | grep -q .
}

if [[ "${BOOTSTRAP:-}" == "1" ]]; then
  if [[ "${PLAN_ONLY:-}" == "1" ]]; then
    log "Planning terraform/shared (BOOTSTRAP=1, PLAN_ONLY=1)"
    terraform -chdir="${SHARED_DIR}" init -input=false
    terraform -chdir="${SHARED_DIR}" plan
  else
    log "Applying terraform/shared (OIDC providers, state bucket, state KMS)"
    terraform -chdir="${SHARED_DIR}" init -input=false
    terraform -chdir="${SHARED_DIR}" apply -auto-approve
  fi
else
  log "Skipping terraform/shared (BOOTSTRAP=1 creates it; needed once per account)"
  if ! shared_already_up; then
    printf '\n\033[1;33mWARNING: shared resources were NOT detected in this account\033[0m\n' >&2
    printf '\033[1;33m(no state bucket / no OIDC provider for this VCS).\033[0m\n' >&2
    printf '\033[1;33mIf this is a bare account, re-run with BOOTSTRAP=1 — main_module will fail without them.\033[0m\n' >&2
  fi
fi

# --- Step 2: render main_module config ---------------------------------------
log "Rendering main_module config (terraform.auto.tfvars + backend.tf)"
"${REPO_ROOT}/scripts/render_tfvars.sh"

# --- Secrets: make tokens reach main_module without interactive prompts -------
# Skip when tokens are already exported, a secrets.auto.tfvars exists, or opted out.
if [[ "${NO_AUTO_SECRETS:-}" != "1" \
      && -z "${TF_VAR_vcs_token:-}${TF_VAR_ai_token:-}${TF_VAR_job_token:-}" \
      && ! -s "${MAIN_DIR}/secrets.auto.tfvars" \
      && -f "${REPO_ROOT}/scripts/tf_env.sh" ]]; then
  log "Resolving secrets via scripts/tf_env.sh (set NO_AUTO_SECRETS=1 to skip)"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/tf_env.sh" ${INSTANCE_ID:+"${INSTANCE_ID}"} || true
fi

# --- Preflight: tools, AWS credentials, required variables and secrets --------
log "Preflight check"
PREFLIGHT_NEED_DOCKER=1
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/preflight.sh"
preflight_main_module

# --- Step 3: main_module (the instance stack) --------------------------------
log "Initialising terraform/main_module"
terraform -chdir="${MAIN_DIR}" init -input=false

if [[ "${PLAN_ONLY:-}" == "1" ]]; then
  log "Planning terraform/main_module (PLAN_ONLY=1)"
  terraform -chdir="${MAIN_DIR}" plan
else
  apply_args=()
  [[ "${AUTO_APPROVE:-}" == "1" ]] && apply_args+=(-auto-approve)
  log "Applying terraform/main_module"
  terraform -chdir="${MAIN_DIR}" apply ${apply_args[@]+"${apply_args[@]}"}
fi

log "Done."
