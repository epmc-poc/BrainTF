# Tag block
environment = "<my_environment>"      # Environment name (e.g., Production, Staging, Development)
team        = "<my_team>"             # Team responsible for the infrastructure
deployed_by = "Terraform"             # Tool for deploying the infrastructure
owner_mail  = "<my_mail@example.com>" # Email address of the infrastructure owner

# Block of common variables
instance_id   = "<my_instance_id>" # Immutable, account-unique id for this BrainTF instance (lowercase, 1-30 chars, e.g. "vasjr"). Independent of the repository name; namespaces all instance-scoped AWS resources.
vcs_repo_name = "<my_project>"     # Name of the project (gitlab or github); used for tagging only
