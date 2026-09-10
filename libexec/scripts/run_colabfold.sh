#!/usr/bin/env bash
# File: run_colabfold.sh
# Description: ColabFold adapter for AI-Assisted OFLOOD — Stage 1 AI structure prediction.
#
# ColabFold requires two separate steps that must be run in different environments:
#
#   Step 1 — MSA generation  (colabfold_batch --msa-only):
#     Requires internet access; run on the LOGIN NODE.
#     Queries the MSA server (MMseqs2 API) to generate an .a3m alignment file.
#
#   Step 2 — Structure prediction  (colabfold_batch):
#     Requires GPU; run on a COMPUTE NODE or GPU-enabled login node.
#     Reads the .a3m file and outputs PDB structures.
#
# The following variables must be set either in run.sh or in the environment:
#   SEQUENCE          — target amino acid sequence (single-letter code)

set -euo pipefail

run_colabfold_main() {
  local _output_dir=""
  local _sequence=""
  local _tmp_dir=""
  local _target_msa_file=""
  local _query_file=""
  local _jid=""
  local -i _n_copied=0
  local _pdb_file=""

  while (($# > 0)); do
    case "$1" in
    --output-dir)
      _output_dir="$2"
      shift 2
      ;;
    --sequence)
      _sequence="$2"
      shift 2
      ;;
    *)
      msg_error "Unknown argument: $1"
      return 1
      ;;
    esac
  done

  if [[ -z "${_output_dir}" ]]; then
    msg_error "Usage: run_colabfold_main --output-dir <dir> [--sequence <seq>]"
    return 1
  fi

  mkdir -p "${_output_dir}"
  _tmp_dir="${_output_dir}/tmp"
  rm -rf "${_tmp_dir}"
  mkdir -p "${_tmp_dir}/prediction"

  # Step 1: MSA generation (login-node step — requires internet)
  _target_msa_file=""
  if [[ -z "${_sequence}" ]]; then
    msg_error "SEQUENCE is not set. Provide the target amino acid sequence in run.sh or the environment."
    return 1
  fi

  msg_info "Step 1 — MSA generation (colabfold_batch)"
  _query_file="${_tmp_dir}/query.fasta"
  printf ">query\n%s\n" "${_sequence}" >"${_query_file}"

  (
    setup_env_ai
    colabfold_batch --msa-only "${_query_file}" "${_tmp_dir}"
  )

  _target_msa_file=$(find "${_tmp_dir}" -name "*.a3m" | head -n 1)
  if [[ -z "${_target_msa_file}" ]]; then
    msg_error "colabfold_batch produced no .a3m file. Check your internet connection and colabfold_batch installation."
    return 1
  fi
  msg_success "MSA generated: ${_target_msa_file}"

  # Step 2: Structure prediction (compute-node step — requires GPU)
  msg_info "Step 2 — Structure prediction (colabfold_batch)"
  msg_info "  models=5, seeds=16, recycles=3, max-msa=16:32"

  _jid=$(submit_ai_job "${_tmp_dir}/prediction" "colabfold_batch" \
    --num-recycle 3 \
    --num-models 5 \
    --num-seeds 16 \
    --max-msa "16:32" \
    "${_target_msa_file}" \
    "${_tmp_dir}/prediction")

  msg_info "Submitted AI Prediction Job (ID: ${_jid}). Waiting for completion..."

  while (($(current_running_jobs "${_jid}") > 0)); do
    sleep 30
  done

  # Copy result PDBs to the designated output directory
  _n_copied=0
  for _pdb_file in "${_tmp_dir}/prediction"/*.pdb; do
    [[ -e "${_pdb_file}" ]] || continue
    cp "${_pdb_file}" "${_output_dir}/"
    ((_n_copied++)) || true
  done

  if ((_n_copied == 0)); then
    msg_error "colabfold_batch produced no PDB files."
    return 1
  fi

  msg_success "ColabFold: ${_n_copied} structure(s) written to ${_output_dir}"

  rm -rf "${_tmp_dir}"
}
