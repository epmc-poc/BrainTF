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
# Env toggles:
#   SKIP_SHARED=1    skip step 1 (shared already applied in this account/region)
#   PLAN_ONLY=1      run 'plan' instead of 'apply' for main_module (dry run)
#   AUTO_APPROVE=1   pass -auto-approve to the main_module apply (non-interactive)
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

# --- Step 1: shared (account-level, run once per account/region) --------------
if [[ "${SKIP_SHARED:-}" == "1" ]]; then
  log "Skipping terraform/shared (SKIP_SHARED=1)"
else
  log "Applying terraform/shared (OIDC providers, state bucket, state KMS)"
  terraform -chdir="${SHARED_DIR}" init -input=false
  terraform -chdir="${SHARED_DIR}" apply -auto-approve
fi

# --- Step 2: render main_module config ---------------------------------------
log "Rendering main_module config (terraform.auto.tfvars + backend.tf)"
"${REPO_ROOT}/scripts/render_tfvars.sh"

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
