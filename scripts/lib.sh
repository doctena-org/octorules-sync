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

# Fail with a helpful message if octorules is not on PATH.
require_octorules() {
  if ! command -v octorules >/dev/null 2>&1; then
    echo "FAIL: octorules not found on PATH. Install it first: pip install 'octorules[wirefilter]'"
    exit 1
  fi
}

# Run a command, capturing stdout and stderr to files while still displaying them.
# Sets _exit_code in the caller's scope.
# Usage: run_capturing <stdout_file> <stderr_file> <command...>
run_capturing() {
  local stdout_file="$1" stderr_file="$2"
  shift 2
  _exit_code=0
  "$@" > >(tee "${stdout_file}") 2> >(tee "${stderr_file}" >&2) || _exit_code=$?
  wait   # ensure tee subprocesses have flushed
  sync   # flush kernel buffers to disk
}

# Warn (but don't fail) if a value is not in the expected set.
# Usage: warn_unexpected "VARNAME" "$value" "val1 val2 val3"
warn_unexpected() {
  local name="$1" value="$2" allowed="$3"
  if [ -z "${value}" ]; then
    return 0
  fi
  for _allowed_val in ${allowed}; do  # intentional word splitting
    if [ "${value}" = "${_allowed_val}" ]; then
      return 0
    fi
  done
  echo "WARN: Unexpected value for ${name}: '${value}'. Expected one of: ${allowed}" >&2
}
