# BrainTF instance deployment.
#
# Deploys the whole stack to the current AWS account in the correct order:
# terraform/shared -> render tfvars -> terraform/main_module.
# See scripts/deploy.sh for env toggles (SKIP_SHARED, PLAN_ONLY, AUTO_APPROVE).

.PHONY: deploy plan

# Full deploy (shared + main_module). Interactive approval on main_module.
deploy:
	@./scripts/deploy.sh

# Dry run: plan main_module instead of applying it.
plan:
	@PLAN_ONLY=1 ./scripts/deploy.sh
