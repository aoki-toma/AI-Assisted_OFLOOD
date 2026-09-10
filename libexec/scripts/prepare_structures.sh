#!/usr/bin/env bash
# File: prepare_structures.sh
# Description: Normalize AI-predicted structure files for the OFLOOD pipeline.
#
# Usage (from pipeline.sh):
#   source prepare_structures.sh
#   prepare_structures_main --output-dir "${_output_dir}"

set -euo pipefail

prepare_structures_main() {
  local _output_dir=""
  local -a _raw_pdbs=()
  local -i _idx=1
  local _pdb_file=""
  local _new_name=""

  while (($# > 0)); do
    case "$1" in
    --output-dir)
      _output_dir="$2"
      shift 2
      ;;
    *)
      msg_error "Unknown parameter passed: $1"
      return 1
      ;;
    esac
  done

  if [[ -z "${_output_dir}" ]]; then
    msg_error "Usage: prepare_structures_main --output-dir <output_dir>"
    return 1
  fi

  mapfile -t _raw_pdbs < <(compgen -G "${_output_dir}/*.pdb" || true)

  if ((${#_raw_pdbs[@]} == 0)); then
    msg_error "No PDB files found to normalize in ${_output_dir}"
    return 1
  fi

  _idx=1
  for _pdb_file in "${_raw_pdbs[@]}"; do
    printf -v _new_name "model_%03d.pdb" "${_idx}"
    local _target_path="${_output_dir}/${_new_name}"

    if [[ -e "${_target_path}" ]]; then
      msg_error "Conflict detected: Target file already exists: ${_target_path}"
      msg_error "Please clean up existing model_*.pdb files or check the directory contents."
      return 1
    fi

    if [[ "${_pdb_file}" != "${_target_path}" ]]; then
      mv "${_pdb_file}" "${_target_path}"
    fi
    ((_idx++))
  done

  msg_success "Normalized ${#_raw_pdbs[@]} PDB file(s) → model_001.pdb … model_$(printf "%03d" "$((${#_raw_pdbs[@]}))").pdb"
}
