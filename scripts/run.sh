#!/bin/bash
# Run octorules plan or sync

# Requires these, provided in action.yml:
# - CONFIG_PATH
# - DOIT
# - FORCE
# - CHECKSUM
# - PHASES
# - ZONES

set -o pipefail

_config_path="${CONFIG_PATH}"
_doit="${DOIT}"
_force="${FORCE}"
_checksum="${CHECKSUM}"
_phases="${PHASES}"
_zones="${ZONES}"

# Output files.
_logfile="${GITHUB_WORKSPACE}/octorules-sync.log"
_planfile="${GITHUB_WORKSPACE}/octorules-sync.plan"

echo "INFO: Cleaning up plan and log files if they already exist"
rm -f "${_logfile}" "${_planfile}"

echo "INFO: config_path: ${_config_path}"

# Build repeated flags from space-separated inputs.
_zone_flags=()
if [ -n "${_zones}" ]; then
  for _z in ${_zones}; do  # intentional word splitting
    _zone_flags+=("--zone" "${_z}")
  done
fi

_phase_flags=()
if [ -n "${_phases}" ]; then
  for _p in ${_phases}; do  # intentional word splitting
    _phase_flags+=("--phase" "${_p}")
  done
fi

if [ "${_doit}" = "--doit" ]; then
  # --- Apply mode: octorules sync --doit ---
  # Global flags (--config, --zone, --phase) must come before the subcommand.
  _cmd=(octorules --config="${_config_path}" "${_zone_flags[@]}" "${_phase_flags[@]}" sync --doit)

  if [ "${_force}" = "Yes" ]; then
    echo "INFO: Running octorules sync with --force"
    _cmd+=(--force)
  fi

  if [ -n "${_checksum}" ]; then
    echo "INFO: Using checksum: ${_checksum}"
    _cmd+=(--checksum "${_checksum}")
  fi

  echo "INFO: Running octorules sync --doit"
  "${_cmd[@]}" 1>"${_planfile}" 2>"${_logfile}"
  _exit_code=$?

  if [ "${_exit_code}" -ne 0 ]; then
    echo "FAIL: octorules sync exited with code ${_exit_code}."
    echo "FAIL: Log output (${_logfile}):"
    cat "${_logfile}"
    if [ -s "${_planfile}" ]; then
      echo "FAIL: Plan output (${_planfile}):"
      cat "${_planfile}"
    fi
    echo "${_exit_code}" >> "${GITHUB_OUTPUT}"
    # Still set outputs before exiting so downstream steps can inspect them.
    {
      echo "exit_code=${_exit_code}"
      echo 'log<<OCTORULES_EOF'
      cat "${_logfile}"
      echo 'OCTORULES_EOF'
      echo 'plan<<OCTORULES_EOF'
      cat "${_planfile}"
      echo 'OCTORULES_EOF'
    } >> "${GITHUB_OUTPUT}"
    exit 1
  fi
else
  # --- Plan mode: octorules plan ---
  # Global flags (--config, --zone, --phase) must come before the subcommand.
  _cmd=(octorules --config="${_config_path}" "${_zone_flags[@]}" "${_phase_flags[@]}" plan --checksum)

  echo "INFO: Running octorules plan"
  "${_cmd[@]}" 1>"${_planfile}" 2>"${_logfile}"
  _exit_code=$?

  if [ "${_exit_code}" -eq 0 ]; then
    echo "INFO: octorules plan completed. No changes detected."
  elif [ "${_exit_code}" -eq 2 ]; then
    echo "INFO: octorules plan detected changes."
  else
    echo "FAIL: octorules plan exited with code ${_exit_code}."
    echo "FAIL: Log output (${_logfile}):"
    cat "${_logfile}"
    if [ -s "${_planfile}" ]; then
      echo "FAIL: Plan output (${_planfile}):"
      cat "${_planfile}"
    fi
    {
      echo "exit_code=${_exit_code}"
      echo 'log<<OCTORULES_EOF'
      cat "${_logfile}"
      echo 'OCTORULES_EOF'
      echo 'plan<<OCTORULES_EOF'
      cat "${_planfile}"
      echo 'OCTORULES_EOF'
    } >> "${GITHUB_OUTPUT}"
    exit 1
  fi
fi

echo "INFO: octorules output has been written to ${_logfile}"

# Extract checksum from plan logfile (plan mode only).
_checksum_value=""
if [ "${_doit}" != "--doit" ] && [ -f "${_logfile}" ]; then
  _checksum_value="$(grep -oP '^checksum=\K[0-9a-f]+' "${_logfile}" || true)"
fi

# Set outputs for downstream steps.
{
  echo "exit_code=${_exit_code}"
  echo "checksum=${_checksum_value}"
  echo 'log<<OCTORULES_EOF'
  cat "${_logfile}"
  echo 'OCTORULES_EOF'
  echo 'plan<<OCTORULES_EOF'
  cat "${_planfile}"
  echo 'OCTORULES_EOF'
} >> "${GITHUB_OUTPUT}"
