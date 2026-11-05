#!/usr/bin/env bash
# lib/preflight.sh — shared preflight checks, sourced by deploy.sh / destroy.sh.
#
# Expects MAIN_DIR to point at terraform/main_module before sourcing.
# Optional: PREFLIGHT_NEED_DOCKER=1 adds a docker warning (deploy only — docker
# is needed at apply time to build the Lambda layer, not on destroy).
#
# Fails fast BEFORE terraform init/plan/apply/destroy. Tokens are checked for
# non-emptiness: vcs_token/ai_token have default="" in variables.tf, so Terraform
# would NOT prompt for them — it would run silently with an empty token (the
# GitHub provider then 404s on the repo and plans to destroy its resources).

_pf_missing=0

# Colored status markers: green = ok, red = failure, yellow = warning.
_pf_pass() { printf '  \033[0;32m*\033[0m %s\n' "$1"; }
_pf_fail() { printf '  \033[0;31m*\033[0m %s\n' "$1"; _pf_missing=1; }
_pf_warn() { printf '  \033[0;33m*\033[0m %s\n' "$1"; }

_pf_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    _pf_pass "tool: $1"
  else
    _pf_fail "tool: $1 — NOT FOUND"
  fi
}

# Value of `key = "..."` / `key = ...` in a tfvars file (empty for missing/empty).
_pf_tfvars_val() { sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"?([^\"]*)\"?.*/\1/p" "$1" | head -n1; }

preflight_main_module() {
  _pf_tool terraform
  _pf_tool aws
  _pf_tool git
  if [[ "${PREFLIGHT_NEED_DOCKER:-}" == "1" ]]; then
    if command -v docker >/dev/null 2>&1; then
      _pf_pass "tool: docker"
    else
      _pf_warn "tool: docker — not found (needed at apply time to build the Lambda layer)"
    fi
  fi

  if aws sts get-caller-identity >/dev/null 2>&1; then
    _pf_pass "AWS credentials (account $(aws sts get-caller-identity --query Account --output text 2>/dev/null))"
  else
    _pf_fail "AWS credentials — sts:GetCallerIdentity failed"
  fi

  local tfvars_file="${MAIN_DIR}/terraform.auto.tfvars"
  if [[ ! -s "${tfvars_file}" ]]; then
    _pf_fail "${tfvars_file} — missing or empty (run ./scripts/render_tfvars.sh first)"
  else
    # Variables that have no default in variables.tf and are rendered by
    # render_tfvars.sh. owner_mail is checked but only warns (it can fall back
    # to the AWS caller ARN inside Terraform).
    local var
    for var in instance_id vcs_provider vcs_hostname vcs_project_path vcs_repo_name \
               environment team deployed_by ai_api_base_url llm_model ai_temperature \
               oidc_provider artifacts_bucket_prefix private_subnet_ids security_groups; do
      if [[ -n "$(_pf_tfvars_val "${tfvars_file}" "${var}")" ]]; then
        _pf_pass "var: ${var}"
      else
        _pf_fail "var: ${var} — missing/empty in terraform.auto.tfvars"
      fi
    done
    if [[ -z "$(_pf_tfvars_val "${tfvars_file}" "owner_mail")" ]]; then
      _pf_warn "var: owner_mail — empty (will fall back to AWS caller ARN in Terraform)"
    fi
  fi

  # Secrets: TF_VAR_* wins; otherwise non-empty value inside secrets.auto.tfvars.
  local env_name key_name val pair
  for pair in "TF_VAR_vcs_token:vcs_token" "TF_VAR_job_token:job_token" "TF_VAR_ai_token:ai_token"; do
    env_name="${pair%%:*}"; key_name="${pair##*:}"; val="${!env_name:-}"
    [[ -z "${val}" && -s "${MAIN_DIR}/secrets.auto.tfvars" ]] \
      && val="$(_pf_tfvars_val "${MAIN_DIR}/secrets.auto.tfvars" "${key_name}")"
    if [[ -n "${val}" ]]; then
      _pf_pass "secret: ${key_name} (<set>)"
    else
      _pf_fail "secret: ${key_name} — missing (TF_VAR_${key_name} or secrets.auto.tfvars)"
    fi
  done

  if [[ "${_pf_missing}" != "0" ]]; then
    printf '\n\033[0;31mPreflight failed: fix the items marked red and re-run.\033[0m\n' >&2
    exit 1
  fi
}
