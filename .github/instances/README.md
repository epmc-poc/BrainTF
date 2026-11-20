# Branch instance overrides

Temporary Terraform settings for a single per-branch BrainTF instance, mainly its
own CI stage toggles.

## How it works

- Create `.github/instances/<instance-id>.tfvars`, where `<instance-id>` is what
  `.github/scripts/instance-id.sh <branch>` prints (e.g. `epmcacmaws-504`).
- On the next push, `deploy-braintf.yml` passes the file to `terraform plan` for
  that instance only. Prod never reads these files.
- The instance publishes its toggles as repository variables named
  `RUN_<STAGE>_<INSTANCE_ID>` (upper case, `-` replaced by `_`), e.g.
  `RUN_CHECKOV_ANALYSIS_EPMCACMAWS_504`.
- `pipeline.yml` uses those variables for pull requests from the instance's
  branch and falls back to the repository-level `RUN_<STAGE>` (prod) variables
  when an instance defines none.

Without a file the instance gets the same toggle values as prod.

## Example

```hcl
# .github/instances/epmcacmaws-504.tfvars
run_tflint_analysis    = true
run_terraform_validate = true
run_checkov_analysis   = false
run_tfsec_analysis     = false
run_trivy_analysis     = false
run_terraform_plan     = false
```

`run_terraform_apply` has no per-instance effect: the apply stage only runs on
pushes to `main`.

## Before merging

Delete the file. The `No instance overrides on merge` job in `pipeline.yml` fails
a pull request while any `.github/instances/*.tfvars` exists. Deleting it
redeploys the instance with the shared defaults, so the last pipeline run on the
pull request uses the same stage set as prod.
