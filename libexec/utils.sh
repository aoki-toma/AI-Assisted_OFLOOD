#!/usr/bin/env bash
# File: utils.sh
# Description: Utility functions for logging and path validation.

if ((BASH_VERSINFO[0] < 4)) || { ((BASH_VERSINFO[0] == 4)) && ((BASH_VERSINFO[1] < 3)); }; then
  echo "[ERROR] Bash 4.3+ is required (found ${BASH_VERSION})" >&2
  exit 1
fi

msg_info() {
  printf "\e[34m[INFO]    [%s] %s\e[0m\n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"
}

msg_success() {
  printf "\e[32m[SUCCESS] [%s] %s\e[0m\n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"
}

msg_error() {
  printf "\e[31m[ERROR]   [%s] %s\e[0m\n" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*" >&2
}

resolve_cmd() {
  local -r _name="$1"
  local _cmd_file
  _cmd_file=$(command -v "${_name}" 2>/dev/null || true)
  if [[ -z "${_cmd_file}" ]]; then
    msg_error "Required command '${_name}' not found in PATH."
    msg_error "Please load the appropriate module or activate the relevant environment."
    exit 1
  fi
  echo "${_cmd_file}"
}

require_cmds() {
  local -a _cmds_list=("$@")
  local _cmd
  for _cmd in "${_cmds_list[@]}"; do
    if ! command -v "${_cmd}" &>/dev/null; then
      msg_error "Required command not found: ${_cmd}"
      exit 1
    fi
  done
  return 0
}

require_file() {
  local -r _target_file="$1"
  if [[ ! -f "${_target_file}" ]]; then
    msg_error "Failed [Action]: Path validation (File not found: ${_target_file})"
    exit 1
  fi
  return 0
}

require_dir() {
  local -r _target_dir="$1"
  if [[ ! -d "${_target_dir}" ]]; then
    msg_error "Failed [Action]: Path validation (Directory not found: ${_target_dir})"
    exit 1
  fi
  return 0
}

has_glob_match() {
  local -r _target_dir="$1"
  local -r _pattern="$2"
  compgen -G "${_target_dir}/${_pattern}" >/dev/null
}

require_glob_match() {
  local -r _target_dir="$1"
  local -r _pattern="$2"
  if ! has_glob_match "${_target_dir}" "${_pattern}"; then
    msg_error "Failed [Action]: Path validation (No files matching '${_pattern}' in ${_target_dir})"
    exit 1
  fi
  return 0
}
