#!/usr/bin/env bash
# Runs BrainTF's Terraform tests from any directory; CI (terraform-tests.yml) uses the same commands.
#
#   scripts/terraform_tests.sh unit                    unit tests: no AWS credentials, network cut where possible
#   scripts/terraform_tests.sh integration             integration tests in the test AWS account (needs AWS credentials)
#   scripts/terraform_tests.sh all                     both
#   scripts/terraform_tests.sh account-setup <action>  plan | apply | destroy the one-time test account setup
#
# JUNIT_DIR=<dir> writes junit-unit.xml / junit-integration.xml there. TERRAFORM=<path> picks the binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/terraform/tests"
TF="$(command -v "${TERRAFORM:-terraform}")"

# Ubuntu 24.04 blocks unprivileged user namespaces, hence the sudo fallback (setpriv drops back to this user).
offline() {
  if unshare -rn true 2>/dev/null; then
    unshare -rn "$@"
  elif sudo -n true 2>/dev/null; then
    sudo -E unshare --net -- setpriv --reuid="$(id -u)" --regid="$(id -g)" --init-groups -- "$@"
  else
    echo "warning: cannot cut the network on this machine; unit tests run with network" >&2
    "$@"
  fi
}

unit() (
  cd "$TESTS/unit"
  "$TF" init -input=false
  "$TF" validate
  local args=()
  if [[ -n "${JUNIT_DIR:-}" ]]; then args=(-junit-xml="$JUNIT_DIR/junit-unit.xml"); fi
  export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_EC2_METADATA_DISABLED=true
  offline "$TF" test "${args[@]}"
)

integration() (
  cd "$TESTS/integration"
  "$TF" init -input=false
  "$TF" validate
  local args=()
  if [[ -n "${JUNIT_DIR:-}" ]]; then args=(-junit-xml="$JUNIT_DIR/junit-integration.xml"); fi
  "$TF" test "${args[@]}"
)

account_setup() (
  local action="${1:-plan}" vars="$ROOT/terraform/main_module"
  [[ "$action" =~ ^(plan|apply|destroy)$ ]] || { echo "account-setup takes plan, apply or destroy" >&2; exit 2; }
  for f in terraform.tfvars secrets.auto.tfvars; do
    [[ -f "$vars/$f" ]] || { echo "Missing $vars/$f: run aws-login.sh (EPAM) or fill it in first." >&2; exit 1; }
  done
  cd "$TESTS/integration/account_setup"
  "$TF" init -input=false
  "$TF" "$action" -compact-warnings -var-file="$vars/terraform.tfvars" -var-file="$vars/secrets.auto.tfvars"
)

case "${1:-}" in
  unit) unit ;;
  integration) integration ;;
  all) rc=0; unit || rc=1; integration || rc=1; exit $rc ;;
  account-setup) account_setup "${2:-}" ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
