#!/usr/bin/env bash
# destroy.sh — tear down this instance's BrainTF resources (terraform/main_module).
#
# terraform/shared is intentionally NOT destroyed here — the shared state bucket,
# OIDC providers and the state KMS key belong to the whole AWS account, are needed
# by other instances and hold this stack's own state file. Remove them by hand in
# terraform/shared only when no instances remain in the account.
#
# Secrets: a valid vcs_token is still required during destroy — the GitHub
# provider must authenticate to delete the repo webhook and variables.
# tf_env.sh is sourced automatically unless NO_AUTO_SECRETS=1 or the values
# are already exported / present in secrets.auto.tfvars.
#
# Env toggles:
#   AUTO_APPROVE=1     pass -auto-approve to 'terraform destroy' (non-interactive)
#   INSTANCE_ID=<id>   instance id for tf_env.sh secret lookup
#   NO_AUTO_SECRETS=1  do not auto-source tf_env.sh (provide secrets yourself)
#
# Usage:
#   ./scripts/destroy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_DIR="${REPO_ROOT}/terraform/main_module"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Secrets (needed by the GitHub provider to delete webhook/variables) ------
if [[ "${NO_AUTO_SECRETS:-}" != "1" \
      && -z "${TF_VAR_vcs_token:-}${TF_VAR_ai_token:-}${TF_VAR_job_token:-}" \
      && ! -s "${MAIN_DIR}/secrets.auto.tfvars" \
      && -f "${REPO_ROOT}/scripts/tf_env.sh" ]]; then
  log "Resolving secrets via scripts/tf_env.sh (set NO_AUTO_SECRETS=1 to skip)"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/tf_env.sh" ${INSTANCE_ID:+"${INSTANCE_ID}"} || true
fi

# --- Step 1: destroy the instance stack ----------------------------------------
[[ -s "${MAIN_DIR}/terraform.auto.tfvars" ]] \
  || die "terraform.auto.tfvars not found — run ./scripts/render_tfvars.sh or 'make deploy' first"

[[ -f "${MAIN_DIR}/backend.tf" ]] \
  || die "backend.tf not found — run ./scripts/render_tfvars.sh first (needed to reach remote state)"

# --- Preflight: same checks as deploy — tools, AWS credentials, variables and
# secrets (a valid vcs_token is required so the GitHub provider can delete the
# repo webhook and variables).
log "Preflight check"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/preflight.sh"
preflight_main_module

log "Initialising terraform/main_module"
terraform -chdir="${MAIN_DIR}" init -input=false

destroy_args=()
[[ "${AUTO_APPROVE:-}" == "1" ]] && destroy_args+=(-auto-approve)

log "Destroying terraform/main_module (instance resources)"
terraform -chdir="${MAIN_DIR}" destroy ${destroy_args[@]+"${destroy_args[@]}"}

log "Instance resources destroyed."
echo "State file for this instance remains under '<instance_id>/main-module/terraform.tfstate'"
echo "in the shared state bucket (harmless leftovers, safe to leave or delete)."

log "Done. Shared (account-level) resources were kept."
