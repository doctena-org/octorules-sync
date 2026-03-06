#!/usr/bin/env bats

# Unit tests for scripts/comment.sh
# Uses PATH-override mocking for gh and git.

setup() {
  export MOCK_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$(mktemp -d)"
  export GITHUB_REPOSITORY="owner/repo"
  export ADD_PR_COMMENT="Yes"
  export PR_COMMENT_TOKEN="ghp_testtoken"
  export PR_NUMBER="42"

  # Create the plan file that comment.sh reads.
  echo "Some plan content here" > "${GITHUB_WORKSPACE}/octorules-sync.plan"

  # File to record gh calls.
  export GH_CALLS_FILE="${MOCK_DIR}/gh.calls"
  touch "${GH_CALLS_FILE}"

  # File to control gh list response (empty = no existing comment).
  export GH_LIST_RESPONSE_FILE="${MOCK_DIR}/gh.list_response"
  echo "" > "${GH_LIST_RESPONSE_FILE}"

  # No-op sleep mock to avoid real delays during retry.
  cat > "${MOCK_DIR}/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "${MOCK_DIR}/sleep"

  # Create mock gh.
  cat > "${MOCK_DIR}/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "${GH_CALLS_FILE}"
# If this is a paginated list call, return the configured response.
if [[ "$*" == *"--paginate"* ]]; then
  cat "${GH_LIST_RESPONSE_FILE}"
  exit 0
fi
exit 0
MOCK
  chmod +x "${MOCK_DIR}/gh"

  # Create mock git.
  cat > "${MOCK_DIR}/git" <<'MOCK'
#!/bin/bash
echo "abc1234"
MOCK
  chmod +x "${MOCK_DIR}/git"

  export PATH="${MOCK_DIR}:${PATH}"

  export SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
}

teardown() {
  rm -rf "${MOCK_DIR}" "${GITHUB_WORKSPACE}"
}

# ---------- Skip / fail conditions ----------

@test "skip when ADD_PR_COMMENT != Yes" {
  ADD_PR_COMMENT="No" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

@test "fail when PR_COMMENT_TOKEN missing" {
  PR_COMMENT_TOKEN="" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL"* ]]
}

@test "fail when PR_COMMENT_TOKEN is 'Not set'" {
  PR_COMMENT_TOKEN="Not set" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL"* ]]
}

@test "skip when PR_NUMBER empty" {
  PR_NUMBER="" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

# ---------- New comment ----------

@test "new comment: calls POST when no existing comment" {
  echo "" > "${GH_LIST_RESPONSE_FILE}"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"POST"* ]]
  [[ "${gh_calls}" == *"issues/42/comments"* ]]
}

# ---------- Update comment ----------

@test "update comment: calls PATCH when existing comment found" {
  echo "99999" > "${GH_LIST_RESPONSE_FILE}"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"PATCH"* ]]
  [[ "${gh_calls}" == *"issues/comments/99999"* ]]
}

# ---------- Comment body ----------

@test "comment body contains marker" {
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"<!-- octorules-sync-plan -->"* ]]
}

@test "comment body contains plan content" {
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"Some plan content here"* ]]
}

# ---------- Lint results in comment ----------

@test "lint file with content: comment body contains Lint Results section" {
  echo "W001: some warning" > "${GITHUB_WORKSPACE}/octorules-sync.lint"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"Lint Results"* ]]
  [[ "${gh_calls}" == *"W001: some warning"* ]]
}

@test "lint file empty: comment body omits lint section when lint disabled" {
  touch "${GITHUB_WORKSPACE}/octorules-sync.lint"
  LINT_EXIT_CODE="" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" != *"Lint Results"* ]]
}

@test "lint clean: comment body shows clean message when lint passed" {
  touch "${GITHUB_WORKSPACE}/octorules-sync.lint"
  LINT_EXIT_CODE="0" run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"Lint Results"* ]]
  [[ "${gh_calls}" == *"clean, no issues found"* ]]
}

@test "lint file missing: comment body omits lint section" {
  rm -f "${GITHUB_WORKSPACE}/octorules-sync.lint"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" != *"Lint Results"* ]]
}

@test "both lint and plan content: comment contains both" {
  echo "E001: some error" > "${GITHUB_WORKSPACE}/octorules-sync.lint"
  echo "Plan: 3 changes" > "${GITHUB_WORKSPACE}/octorules-sync.plan"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"Lint Results"* ]]
  [[ "${gh_calls}" == *"E001: some error"* ]]
  [[ "${gh_calls}" == *"Plan: 3 changes"* ]]
}

# ---------- Missing plan file ----------

@test "missing plan file: comment shows fallback message" {
  rm -f "${GITHUB_WORKSPACE}/octorules-sync.plan"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"No plan output"* ]]
}

# ---------- Retry behavior ----------

@test "comment lookup retries on transient gh api failure" {
  # Counter file tracks list call attempts.
  local counter_file="${MOCK_DIR}/list_counter"
  echo "0" > "${counter_file}"

  # gh mock: first list call fails, second succeeds with no existing comment.
  cat > "${MOCK_DIR}/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "${GH_CALLS_FILE}"
if [[ "\$*" == *"--paginate"* ]]; then
  count=\$(cat "${counter_file}")
  count=\$((count + 1))
  echo "\${count}" > "${counter_file}"
  if [ "\${count}" -lt 2 ]; then
    exit 1
  fi
  cat "${GH_LIST_RESPONSE_FILE}"
  exit 0
fi
exit 0
MOCK
  chmod +x "${MOCK_DIR}/gh"

  echo "" > "${GH_LIST_RESPONSE_FILE}"
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  # Should still create a new comment after successful retry.
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"POST"* ]]
}

# ---------- Comment body edge cases ----------

@test "comment body handles backticks and code fences in plan" {
  cat > "${GITHUB_WORKSPACE}/octorules-sync.plan" <<'PLAN'
Here is some code:
\`\`\`yaml
key: value
\`\`\`
And an inline \`backtick\`.
PLAN
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"key: value"* ]]
}

@test "git log failure: sha falls back to unknown" {
  # Replace git mock with one that fails.
  cat > "${MOCK_DIR}/git" <<'MOCK'
#!/bin/bash
exit 128
MOCK
  chmod +x "${MOCK_DIR}/git"

  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"unknown"* ]]
}

@test "comment body handles markdown table in plan" {
  cat > "${GITHUB_WORKSPACE}/octorules-sync.plan" <<'PLAN'
| Zone     | Phase       | Action |
|----------|-------------|--------|
| a.com    | cache_rules | create |
PLAN
  run bash "${SCRIPT_DIR}/comment.sh"
  [ "${status}" -eq 0 ]
  gh_calls="$(cat "${GH_CALLS_FILE}")"
  [[ "${gh_calls}" == *"a.com"* ]]
  [[ "${gh_calls}" == *"cache_rules"* ]]
}
