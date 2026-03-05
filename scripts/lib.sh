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
random_delim() {
  local prefix="$1"
  echo "${prefix}_$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}
