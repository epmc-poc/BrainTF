# Bootstrap State Management

## Overview

The BrainTF project uses multiple Terraform state files stored in S3. This document covers:

1. [Bootstrap state management](#bootstrap-state-management) — where the bootstrap module stores its own state.
2. [Pipeline state management](#pipeline-state-management) — where the CI/CD pipeline stores its Terraform state.

---

## Bootstrap State Management

### What bootstrap creates

The `bootstrap` module creates the AWS infrastructure required to store Terraform state remotely:

- **S3 bucket** — `backend-state-bucket-{vcs_repo_name}-{region}` (stores `main_module` state)
- **KMS key** — `alias/kms_key_{vcs_repo_name}_{region}` (encrypts state files)
- **IAM role** — `Terraform-role-{vcs_repo_name}-{region}`

After a successful `terraform apply`, bootstrap automatically generates `terraform/main_module/backend.generated.tf` with the backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket       = "backend-state-bucket-{vcs_repo_name}-{region}"
    key          = "main-module/terraform.tfstate"
    region       = "{region}"
    encrypt      = true
    use_lockfile = true
  }
}
```

### The Problem

By default, bootstrap's own Terraform state is stored **locally** on the machine that ran `terraform apply` (a `terraform.tfstate` file in the `terraform/bootstrap/` directory).

This creates a risk: if the machine is lost or the file is deleted, you lose the ability to manage bootstrap resources (update or destroy them).

### Options for Managing Bootstrap State

#### Option 1: Store state in the git repository

Commit `terraform.tfstate` to the repository.

> This approach can be used to store **ONLY** this particular state file. Other state files must not be stored in VCS, since Terraform state files might contain sensitive data. Storing them in git exposes this data to everyone with repository access.
>
> Consider moving to Option 2 if there is a requirement to encrypt **all** Terraform state files.

#### Option 2: Migrate state to S3 (recommended)

After bootstrap creates the S3 bucket, migrate the local bootstrap state into that same bucket.

##### Steps

1. Run bootstrap as usual:

   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply
   ```

2. Add a backend configuration to `terraform/bootstrap/main.tf`:

   ```hcl
   terraform {
     backend "s3" {
       bucket       = "backend-state-bucket-{vcs_repo_name}-{region}"
       key          = "bootstrap/terraform.tfstate"
       region       = "{region}"
       encrypt      = true
       use_lockfile = true
     }
   }
   ```

   > Use a different `key` than `main_module` (e.g. `bootstrap/terraform.tfstate`) to avoid overwriting.

3. Migrate the local state to S3:

   ```bash
   terraform init -migrate-state
   ```

   Terraform will detect the new backend and ask to copy the existing local state to S3. Confirm with `yes`.

4. Verify the migration — check that the state file appears in the S3 bucket:

   ```bash
   aws s3 ls s3://backend-state-bucket-{vcs_repo_name}-{region}/bootstrap/
   ```

5. The local `terraform.tfstate` file in `terraform/bootstrap/` is no longer needed. It can be deleted or added to `.gitignore`.

##### Result

| Module      | State location | S3 key                          |
|-------------|----------------|---------------------------------|
| bootstrap   | Remote S3      | `bootstrap/terraform.tfstate`   |
| main_module | Remote S3      | `main-module/terraform.tfstate` |

Both modules now store state in the same S3 bucket, protected by KMS encryption and S3 versioning.

---

## Pipeline State Management

### Overview

The CI/CD pipeline (`terraform-plan` and `terraform-apply` stages) needs its own Terraform state file to track infrastructure deployed from the working directories (`WORK_DIRS`). This state is **separate** from the `main_module` state.

The `main_module` automatically:
1. Determines which S3 bucket to use for pipeline state.
2. Creates a prefix (folder) in that bucket for the pipeline state file.
3. Exports the full backend configuration string as a VCS CI/CD variable (`TERRAFORM_BACKEND_PARAMS`).

### Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `pipeline_state_bucket` | Name of the S3 bucket for pipeline state. Leave **empty** to reuse the bootstrap state bucket. | `""` (empty) |
| `pipeline_state_key` | The S3 object key (path) for the pipeline state file. | `pipeline/terraform.tfstate` |

These are configured in `terraform/main_module/terraform.tfvars`:

```hcl
# Pipeline state backend configuration
pipeline_state_bucket = ""                           # (Optional) Name of an existing S3 bucket for pipeline state.
pipeline_state_key    = "pipeline/terraform.tfstate" # S3 key (path) for pipeline state within the chosen bucket.
```

---

### Scenario A: Use the bootstrap state bucket (default)

This is the simplest option — no additional buckets are needed.

**When to use:** You want to keep everything in a single bucket managed by bootstrap.

#### How it works

1. Leave `pipeline_state_bucket` empty (`""`).
2. The `main_module` automatically resolves the bootstrap state bucket name using the same formula:
   ```
   backend-state-bucket-{vcs_repo_name}-{region}
   ```
3. A prefix (folder) is created inside the bucket based on `pipeline_state_key`. For the default key `pipeline/terraform.tfstate`, the created prefix is `pipeline/`.
4. The pipeline uses this backend configuration at runtime:
   ```
   -backend-config=bucket=backend-state-bucket-{vcs_repo_name}-{region}
   -backend-config=key=pipeline/terraform.tfstate
   -backend-config=region={region}
   -backend-config=kms_key_id={kms_key_arn}
   -backend-config=encrypt=true
   -backend-config=use_lockfile=true
   ```

#### Resulting bucket structure

```
backend-state-bucket-{vcs_repo_name}-{region}/
├── bootstrap/terraform.tfstate       # (if Option 2 above was used)
├── main-module/terraform.tfstate     # main_module state
└── pipeline/terraform.tfstate        # pipeline state (created by CI/CD)
```

#### Configuration example

```hcl
# terraform/main_module/terraform.tfvars
pipeline_state_bucket = ""                           # Empty → reuse bootstrap bucket
pipeline_state_key    = "pipeline/terraform.tfstate" # Folder "pipeline/" will be auto-created
```

---

### Scenario B: Use a custom (user-provided) S3 bucket

Use an existing S3 bucket that you manage independently (e.g., a shared bucket across multiple projects).

**When to use:**
- You want to separate pipeline state from bootstrap infrastructure.
- You have an existing bucket with specific policies, encryption, or cross-account access.

#### Prerequisites

The custom bucket must:
- Already exist in your AWS account.
- Have appropriate IAM permissions for the pipeline role to `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`.
- Preferably have versioning and encryption enabled.

#### How it works

1. Set `pipeline_state_bucket` to the name of your existing bucket.
2. The `main_module` creates a prefix (folder) in the specified bucket based on `pipeline_state_key`. For example, key `my-project/terraform.tfstate` results in folder `my-project/`.
3. The pipeline uses this backend configuration at runtime:
   ```
   -backend-config=bucket=my-custom-state-bucket
   -backend-config=key=my-project/terraform.tfstate
   -backend-config=region={region}
   -backend-config=kms_key_id={kms_key_arn}
   -backend-config=encrypt=true
   -backend-config=use_lockfile=true
   ```

#### Resulting bucket structure

```
my-custom-state-bucket/
└── my-project/terraform.tfstate   # pipeline state (created by CI/CD)
```

The bootstrap bucket remains untouched by pipeline state:

```
backend-state-bucket-{vcs_repo_name}-{region}/
├── bootstrap/terraform.tfstate       # (if Option 2 above was used)
└── main-module/terraform.tfstate     # main_module state only
```

#### Configuration example

```hcl
# terraform/main_module/terraform.tfvars
pipeline_state_bucket = "my-custom-state-bucket"          # Your existing bucket
pipeline_state_key    = "my-project/terraform.tfstate"    # Folder "my-project/" will be auto-created
```

---

### How the prefix (folder) is created

In both scenarios, the `main_module` creates an empty S3 object acting as the folder prefix:

```hcl
resource "aws_s3_object" "pipeline_state_prefix" {
  bucket  = local.pipeline_state_bucket
  key     = replace(var.pipeline_state_key, "/[^/]+$/", "")  # Strips filename, keeps path
  content = ""
  tags    = local.tags
}
```

For `pipeline_state_key = "pipeline/terraform.tfstate"`, this creates the object with key `pipeline/` in the target bucket.

For `pipeline_state_key = "envs/dev/terraform.tfstate"`, this creates the object with key `envs/dev/` in the target bucket.

> **Note:** The actual state file (`terraform.tfstate`) is written by Terraform during `terraform init` in the pipeline. The `aws_s3_object` resource only ensures the parent folder exists beforehand.
