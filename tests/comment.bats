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
