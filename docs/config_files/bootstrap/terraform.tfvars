# Tag block
environment = "<my_environment>"      # Environment name (e.g., Production, Staging, Development)
team        = "<my_team>"             # Team responsible for the infrastructure
deployed_by = "Terraform"             # Tool for deploying the infrastructure
owner_mail  = "<my_mail@example.com>" # Email address of the infrastructure owner

# Block of common variables
account_id    = "<my_account_id>" # AWS account ID
region        = "<my_region>"     # AWS region where resources will be deployed
vcs_repo_name = "<my_project>"    # Name of the project

# State backend configuration
state_bucket_name = ""          # Name of an already existing S3 bucket for Terraform state
state_key_prefix  = "pipeline/" # Optional: directory prefix inside the bucket (must end with '/'); leave empty "" for bucket root
