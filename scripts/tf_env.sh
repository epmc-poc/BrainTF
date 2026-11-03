#!/usr/bin/env bash
# tf_env.sh — export TF_VAR_* for terraform plan/apply WITHOUT secrets.auto.tfvars.
#
# Usage (must be SOURCED, not executed):
#   source ./scripts/tf_env.sh                  # instance_id 'smoke', provider auto
#   source ./scripts/tf_env.sh smoke2           # explicit instance_id
#   source ./scripts/tf_env.sh smoke3 gitlab    # explicit VCS provider
#
# Resolution order per variable (first non-empty wins):
#   1. already-exported TF_VAR_*
#   2. SSM file /Brain-TF/manual/<provider>/main_module/secrets.auto.tfvars
#      (SecureString with job_token / vcs_token / ai_token).
#      vcs_token and job_token from this file are used ONLY when the repo owner
#      is a shared org (BRAINTF_ORG_OWNERS, default "epmc-poc") — service tokens
#      cannot see repositories under personal accounts.
#   3. Personal GitHub PAT from ~/.git-credentials (vcs_token, job_token)
#   4. Per-instance SSM parameter /<instance_id>/ai_token (ai_token only)
#
# ai_token is repo-independent and is always taken from the shared file first.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "tf_env.sh must be sourced: source $0 [instance_id] [vcs_provider]" >&2
  exit 1
fi

INSTANCE_ID="${1:-smoke}"

# --- Detect repo owner / host from git remote (optional) ----------------------
det_owner=""; det_host=""
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  remote="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "${remote}" ]]; then
    first_remote="$(git remote 2>/dev/null | head -n1 || true)"
    [[ -n "${first_remote}" ]] && remote="$(git remote get-url "${first_remote}" 2>/dev/null || true)"
  fi
  remote="${remote%.git}"
  if [[ "${remote}" =~ ^git@([^:]+):(.+)$ ]]; then
    det_host="${BASH_REMATCH[1]}"; det_path="${BASH_REMATCH[2]}"
  elif [[ "${remote}" =~ ^https?://([^/]+)/(.+)$ ]]; then
    det_host="${BASH_REMATCH[1]}"; det_path="${BASH_REMATCH[2]}"
  fi
  det_owner="${det_path%%/*}"
fi

if [[ -z "${2:-}" ]]; then
  [[ "${det_host}" == *gitlab* ]] && VCS_PROVIDER="gitlab" || VCS_PROVIDER="github"
else
  VCS_PROVIDER="$2"
fi

ORG_OWNERS="${BRAINTF_ORG_OWNERS:-epmc-poc}"
org_repo=false
for o in ${ORG_OWNERS}; do
  [[ "${det_owner}" == "${o}" ]] && org_repo=true && break
done

# --- Helpers ------------------------------------------------------------------
_ssm_val() {
  aws ssm get-parameter --name "$1" --with-decryption \
    --query 'Parameter.Value' --output text 2>/dev/null || true
}
_kv() { # extract `key = "value"` from tfvars text
  printf '%s\n' "$1" | sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" | head -n1
}

# --- Shared secrets file in SSM -----------------------------------------------
ssm_file=""
if command -v aws >/dev/null 2>&1; then
  ssm_file="$(_ssm_val "/Brain-TF/manual/${VCS_PROVIDER}/main_module/secrets.auto.tfvars")"
fi
f_vcs_token="$(_kv "${ssm_file}" vcs_token)"
f_job_token="$(_kv "${ssm_file}" job_token)"
f_ai_token="$(_kv "${ssm_file}" ai_token)"

# --- Resolve ------------------------------------------------------------------
# ai_token: env > shared file > per-instance SSM param
if [[ -z "${TF_VAR_ai_token:-}" ]]; then
  TF_VAR_ai_token="${f_ai_token}"
fi
if [[ -z "${TF_VAR_ai_token:-}" ]] && command -v aws >/dev/null 2>&1; then
  TF_VAR_ai_token="$(_ssm_val "/${INSTANCE_ID}/ai_token")"
fi
export TF_VAR_ai_token

# vcs_token / job_token: env > shared file (org repos only) > personal PAT
pat=""
if [[ "${org_repo}" == "true" && -n "${f_vcs_token}" ]]; then
  TF_VAR_vcs_token="${TF_VAR_vcs_token:-${f_vcs_token}}"
  TF_VAR_job_token="${TF_VAR_job_token:-${f_job_token}}"
fi
if [[ -z "${TF_VAR_vcs_token:-}" ]]; then
  pat="$(grep 'github.com' ~/.git-credentials 2>/dev/null \
    | sed -E 's#https?://[^:]+:([^@]+)@.*#\1#' | head -n1 || true)"
  TF_VAR_vcs_token="${pat}"
fi
export TF_VAR_vcs_token
export TF_VAR_job_token="${TF_VAR_job_token:-${TF_VAR_vcs_token}}"

# --- Report -------------------------------------------------------------------
for v in TF_VAR_vcs_token TF_VAR_job_token TF_VAR_ai_token; do
  if [[ -n "${!v:-}" ]]; then
    echo "exported ${v} (<set>)"
  else
    echo "WARNING: ${v} is empty" >&2
  fi
done
