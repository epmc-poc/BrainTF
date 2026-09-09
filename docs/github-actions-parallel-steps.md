# GitHub Actions parallel steps (EPMCACMAWS-497)

Follow-up to EPMCACMAWS-463. GitHub added in-job concurrency on 2026-06-25: `background`, `wait`, `wait-all`, `cancel`, and `parallel`.

Official references:

- [Changelog](https://github.blog/changelog/2026-06-25-actions-steps-can-now-be-run-in-parallel/)
- [Workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

## Working syntax

`parallel:` is an item **inside `steps:`**, not a job-level key.

The 463 sandbox (`.github/workflows/test-parallel-steps.yml`, runs on 11 Aug) failed immediately with **Invalid workflow file**, 0 jobs. The file used `wait-all: true`. Current docs require `wait-all:` with **no value**.

```yaml
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - parallel:
          - name: Install TFSec
            run: curl ...
          - name: Install Python tools
            run: pip install --user openai "checkov==${CHECKOV_VERSION}"

      - name: Verify
        run: tfsec --version && checkov --version
```

Equivalent explicit form:

```yaml
      - name: Install TFSec
        id: tfsec
        run: curl ...
        background: true

      - name: Install Python tools
        id: python-tools
        run: pip install --user openai "checkov==${CHECKOV_VERSION}"
        background: true

      - name: Wait for installs
        wait: [tfsec, python-tools]
```

Rules that matter for this repo:

- At most 10 background steps per job.
- `uses:` is allowed on background/parallel steps; `GITHUB_ENV` / `GITHUB_PATH` / outputs are visible only after `wait` / the implicit wait of `parallel`.
- Do not run two `pip install --user` commands in parallel — they write the same `~/.local` tree.
- Composite actions cannot declare `background`/`parallel` internally.

Isolated verification workflow: [parallel-steps-sandbox.yml](../.github/workflows/parallel-steps-sandbox.yml). It must include a `push` trigger: `workflow_dispatch` alone does not show the workflow in Actions on a feature branch.

## What is parallel in `pipeline.yml`

Safe (independent, no AI writes):

- `terraform-fmt` no longer waits for `setup`. After `validate-work-dirs`, format and tool install overlap.
- In `setup`, TFSec download runs next to a **single** `pip install` of OpenAI + Checkov.
- After `checkout`, each job installs its tool, restores `~/.local`, and assumes the AWS role in a `parallel:` group.

Not safe — analysis jobs stay sequential via `needs:`:

`tflint` → `validate` → `checkov` → `tfsec` → `trivy` → `plan`

Each failing analysis job uploads a log to S3 (`ACTION=both`), which triggers AI Handler. The handler deletes `artifacts/{PR}/` and uploads a new set of proposed files. Two tools at once would:

- comment overlapping, contradictory fixes on the same PR;
- overwrite each other's S3 artifacts (last writer wins);
- fix the original commit independently, so a Checkov rewrite can remove a name that TFLint just tried to correct.

That is product behavior, not a limitation of the Actions syntax. Job-level `needs:` already could fan out those jobs; we still must not.

## How to re-test

1. Push a commit that changes `.github/workflows/parallel-steps-sandbox.yml` (a `push` trigger is required). A run appears under Actions → **Parallel steps sandbox**.
2. Confirm `syntax-parallel` wall-clock is about one `sleep`, not ~10s.
3. Confirm `syntax-background` prints `bg-worker result=ok`.
4. Confirm `syntax-wait-all` succeeds (`wait-all:` empty, not `true`).
5. Confirm `last-writer-wins` keeps only the Checkov fake fix.
6. Run **CI Pipeline** and compare setup/fmt duration. Analysis order must stay unchanged.
