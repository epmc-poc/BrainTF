# Tag block
environment = "<my_environment>"      # Environment name (e.g., Production, Staging, Development)
team        = "<my_team>"             # Team responsible for the infrastructure
deployed_by = "<deploy_method>"       # Deployment method (e.g. terraform, ci)
owner_mail  = "<my_mail@example.com>" # Email address of the infrastructure owner

# Block of common variables
account_id    = "<my_account_id>" # AWS account ID
region        = "<my_region>"     # AWS region where resources will be deployed
vcs_repo_name = "<my_project>"    # Name of the project

# State backend configuration
platform_state_bucket_prefix = "<my-platform-state-bucket-prefix>" # Prefix for the platform state S3 bucket name (stores bootstrap + main_module state). Final name: <prefix>-<vcs_repo_name>-<region>. Must match the value used in main_module.
