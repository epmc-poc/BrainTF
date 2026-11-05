# BrainTF instance deployment.
#
# Deploys the whole stack to the current AWS account in the correct order:
# terraform/shared -> render tfvars -> terraform/main_module.
# See scripts/deploy.sh for env toggles (BOOTSTRAP, PLAN_ONLY, AUTO_APPROVE).

.PHONY: deploy plan destroy

# Full deploy (shared + main_module). Interactive approval on main_module.
deploy:
	@./scripts/deploy.sh

# Dry run: plan main_module instead of applying it.
plan:
	@PLAN_ONLY=1 ./scripts/deploy.sh

# Tear down this instance's AWS resources (terraform/main_module only).
# terraform/shared (account-level) is kept; interactive approval required.
destroy:
	@./scripts/destroy.sh
