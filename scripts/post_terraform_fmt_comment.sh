#!/usr/bin/env bash
set -euo pipefail

log_file="$GITHUB_WORKSPACE/terraform_fmt_check.log"
comment_file="$RUNNER_TEMP/terraform_fmt_comment.md"

if [[ "$FORMAT_REQUIRED" != "true" && "$FORMAT_ERROR" != "true" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "Terraform formatting passed. No corrections needed."
  exit 0
fi

author="$(gh api "repos/$GITHUB_REPOSITORY/commits/$SOURCE_SHA" --jq '.author.login // .commit.author.name')"

cat > "$comment_file" <<EOF
:arrow_up: Job message

---

The analysis process is complete for Terraform Format Check stage

---

<details><summary>Show utility outputs</summary>

EOF

if [[ "$FORMAT_ERROR" == "true" ]]; then
  cat >> "$comment_file" <<'EOF'
Terraform formatting could not complete. Correct the syntax or formatter errors manually.
The \`bot format approve\` command cannot repair invalid HCL.

EOF
  printf '```text\n' >> "$comment_file"
  cat "$log_file" >> "$comment_file"
  printf '\n```\n' >> "$comment_file"
else
  cat >> "$comment_file" <<'EOF'
Terraform formatting is required. To apply it automatically, comment: \`bot format approve\`

EOF
  # Extract Terraform diff hunks; directory headings and file listings are not diff syntax.
  awk '
    /^Checking formatting in / { directory = substr($0, 24); next }
    /^--- old\// {
      if (directory != "") { printf "Checking formatting in `%s`\n\n", directory; directory = "" }
      next
    }
  ' "$log_file" >> "$comment_file"
  printf '```diff\n' >> "$comment_file"
  awk '
    /^--- old\// { in_diff = 1 }
    /^Checking formatting in / { in_diff = 0 }
    in_diff && /^(--- old\/|\+\+\+ new\/|@@|[ +\-]|\\ No newline)/ { print }
  ' "$log_file" >> "$comment_file"
  printf '```\n' >> "$comment_file"
fi

cat >> "$comment_file" <<EOF

</details>

___

<details><summary>Show job details</summary>

- **Job Name:** Terraform Format Check
- **Merge/Pull Request Number:** $PR_NUMBER
- **Commit SHA:** $SOURCE_SHA
- **Commit Author:** $author
- **Log file:** No log uploaded to S3
- **Console Logs:** [View the job log]($GITHUB_RUN_URL)

</details>
EOF

gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body-file "$comment_file"
