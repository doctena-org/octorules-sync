#!/bin/bash
# Shared utilities for octorules-sync scripts.

# Retry a command with exponential backoff.
# Usage: retry <max_retries> <initial_delay_seconds> <command...>
# Stdout from the successful attempt is preserved.
# Warnings are sent to stderr to not interfere with stdout capture.
# Returns the exit code of the last attempt.
retry() {
  local max_retries="$1" delay="$2"
  shift 2
  local attempt=1 exit_code=0
  while [ "${attempt}" -le "${max_retries}" ]; do
    exit_code=0
    "$@" || exit_code=$?
    if [ "${exit_code}" -eq 0 ]; then
      return 0
    fi
    if [ "${attempt}" -lt "${max_retries}" ]; then
      echo "WARN: Attempt ${attempt}/${max_retries} failed (exit ${exit_code}). Retrying in ${delay}s..." >&2
      sleep "${delay}"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  return "${exit_code}"
}

# Generate a random heredoc delimiter with the given prefix.
# Usage: _delim="$(random_delim OCTORULES_EOF)"
# Reads 16 bytes from /dev/urandom → 32 hex chars, sufficient to prevent
# collision with any content in heredoc output.
random_delim() {
  local prefix="$1"
  echo "${prefix}_$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

# Build repeated CLI flags from a space-separated string.
# Usage: build_flags _array_name "--zone" "a.com b.com"
# After the call, the named array contains e.g. ("--zone" "a.com" "--zone" "b.com").
build_flags() {
  local -n _arr="$1"
  local flag="$2" values="$3"
  _arr=()
  if [ -n "${values}" ]; then
    for _v in ${values}; do  # intentional word splitting
      _arr+=("${flag}" "${_v}")
    done
  fi
}

# Print a file with GitHub Actions workflow command tags escaped so they
# are not interpreted as log annotations. The original file is not modified.
# Usage: escape_actions_tags <file>
escape_actions_tags() {
  sed 's/\[WARNING\]/[WARNING ]/g; s/\[ERROR\]/[ERROR ]/g' "$1"
}
