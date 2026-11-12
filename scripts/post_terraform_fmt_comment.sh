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
The `bot format approve` command cannot repair invalid HCL.

EOF
  printf '```text\n' >> "$comment_file"
  cat "$log_file" >> "$comment_file"
  printf '\n```\n' >> "$comment_file"
else
  cat >> "$comment_file" <<'EOF'
Terraform formatting is required. To apply it automatically, comment: `bot format approve`

EOF
  # Keep file labels outside their Markdown diff blocks.
  directory=""
  in_diff=false
  while IFS= read -r line; do
    case "$line" in
      "Checking formatting in "*)
        if [[ "$in_diff" == true ]]; then
          printf '```\n\n'
          in_diff=false
        fi
        directory="${line#Checking formatting in }"
        ;;
      "--- old/"*)
        if [[ "$in_diff" == true ]]; then
          printf '```\n\n'
        fi
        file="${line#--- old/}"
        printf 'Checking formatting in `%s`, `%s`\n\n' "${directory:-${file%/*}}" "$file"
        printf '```diff\n%s\n' "$line"
        in_diff=true
        ;;
      "+++ new/"*|"@@ "*|" "*|"+"*|"-"*|"\\ No newline"*)
        if [[ "$in_diff" == true ]]; then
          printf '%s\n' "$line"
        fi
        ;;
    esac
  done < "$log_file" >> "$comment_file"
  if [[ "$in_diff" == true ]]; then
    printf '```\n' >> "$comment_file"
  fi
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
