#!/usr/bin/env bash
# File: run_oflood.sh
# Description: Orchestrates OFLOOD short-MD cycles and production MD.

set -euo pipefail

: "${AA_OFLOOD_ROOT:?AA_OFLOOD_ROOT is not set}"
: "${PROJECT_DIR:?PROJECT_DIR is not set}"

prepare_seeds() {
  local -r _cycle_id="$1"
  local -r _initial_seed_dir="$2"
  local -r _engine="$3"
  local -r _frame_dt_ps="$4"
  local -r _work_root_dir="$5"
  local _current_cycle_dir=""
  local _seed_ext=""
  local _traj_file_name=""
  local _top_file=""
  local _output_ext=""
  local -a _seeds=()
  local -i _seed_idx=1
  local _seed=""
  local _md_dir=""
  local _prev_cycle_dir=""
  local _selection_file=""
  local -r _extract_frames_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/extract_frames.sh"

  printf -v _current_cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"

  if [[ -d "${_current_cycle_dir}/md_001" ]]; then
    msg_info "Skipping [Action]: Prepare Seeds - Target directory already exists."
    return 0
  fi

  msg_info "Starting [Action]: Prepare Seeds (cycle_$(printf "%03d" "${_cycle_id}"))"

  mkdir -p "${_current_cycle_dir}"

  case "${_engine}" in
  gromacs)
    _seed_ext="gro"
    _traj_file_name="md.xtc"
    _top_file="md.tpr"
    _output_ext="gro"
    require_cmds "${GMX_CMD}"
    ;;
  amber)
    _seed_ext="ncrst"
    _traj_file_name="md.nc"
    _top_file=""
    _output_ext="ncrst"
    require_cmds cpptraj
    ;;
  *)
    msg_error "Unknown engine: ${_engine}"
    return 1
    ;;
  esac

  if ((_cycle_id == 1)); then
    require_glob_match "${_initial_seed_dir}" "*.${_seed_ext}"

    mapfile -t _seeds < <(compgen -G "${_initial_seed_dir}/*.${_seed_ext}" || true)

    _seed_idx=1
    for _seed in "${_seeds[@]}"; do
      printf -v _md_dir "%s/md_%03d" "${_current_cycle_dir}" "${_seed_idx}"
      mkdir -p "${_md_dir}"
      cp "${_seed}" "${_md_dir}/mdin.${_output_ext}"
      ((_seed_idx++)) || true
    done

    msg_success "Completed [Action]: Prepare Seeds (cycle_$(printf "%03d" "${_cycle_id}"))"
    return 0
  fi

  printf -v _prev_cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "$((_cycle_id - 1))"

  _selection_file="${_prev_cycle_dir}/analysis/selected_seeds.txt"
  require_file "${_selection_file}"

  # shellcheck source=/dev/null
  source "${_extract_frames_script_file}"
  extract_frames_from_seeds \
    --engine "${_engine}" \
    --seed-file "${_selection_file}" \
    --work-root "${_work_root_dir}" \
    --out-dir "${_current_cycle_dir}" \
    --frame-dt-ps "${_frame_dt_ps}" \
    --is-production "false" \
    --top-file "${_topology_file}"

  msg_success "Completed [Action]: Prepare Seeds (cycle_$(printf "%03d" "${_cycle_id}"))"
}

run_parallel_md() {
  local -r _cycle_id="$1"
  local -r _engine="$2"
  local -r _md_input_file="$3"
  local -r _topology_file="$4"
  local -r _work_root_dir="$5"
  local -r _job_type="${6:-sampling}"
  local _cycle_dir=""
  local -a _job_ids=()
  local -a _submitted_md_dirs=()
  local -a _md_dirs=()
  local _jid=""
  local _md_dir=""
  local _running=""
  local _ec=""

  printf -v _cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"

  if [[ -f "${_cycle_dir}/md_001/md.xtc" ]] || [[ -f "${_cycle_dir}/md_001/md.nc" ]]; then
    msg_info "Skipping [Action]: Run Parallel MD - Trajectory files already exist."
    return 0
  fi

  msg_info "Starting [Action]: Run Parallel MD (cycle_$(printf "%03d" "${_cycle_id}"), engine=${_engine})"

  require_dir "${_cycle_dir}"
  require_file "${_md_input_file}"
  require_file "${_topology_file}"

  : "${MAX_CONCURRENT_JOBS:?MAX_CONCURRENT_JOBS is not set}"

  _job_ids=()
  _submitted_md_dirs=()
  mapfile -t _md_dirs < <(compgen -G "${_cycle_dir}/md_*" || true)

  case "${_engine}" in
  gromacs)
    require_cmds "${GMX_CMD}"

    for _md_dir in "${_md_dirs[@]}"; do
      require_file "${_md_dir}/mdin.gro"

      if ! "${GMX_CMD}" grompp \
        -f "${_md_input_file}" \
        -c "${_md_dir}/mdin.gro" \
        -p "${_topology_file}" \
        -o "${_md_dir}/md.tpr" \
        -po "${_md_dir}/mdout.mdp" \
        -maxwarn 1 >"${_md_dir}/grompp.log" 2>&1; then
        msg_error "grompp failed for ${_md_dir}. See: ${_md_dir}/grompp.log"
        exit 1
      fi

      while (($(current_running_jobs "${_job_ids[@]}") >= MAX_CONCURRENT_JOBS)); do
        if declare -f adapter_wait_any >/dev/null; then adapter_wait_any; else sleep 30; fi
      done

      submit_md_job "${_job_type}" "${_md_dir}" \
        "${GMX_CMD}" mdrun -deffnm md >"${_md_dir}/.jid_tmp"
      _jid=$(cat "${_md_dir}/.jid_tmp")
      rm -f "${_md_dir}/.jid_tmp"
      _job_ids+=("${_jid}")
      _submitted_md_dirs+=("${_md_dir}")
    done
    ;;

  amber)
    require_cmds "${AMBER_MD_CMD}"

    for _md_dir in "${_md_dirs[@]}"; do
      require_file "${_md_dir}/mdin.ncrst"

      while (($(current_running_jobs "${_job_ids[@]}") >= MAX_CONCURRENT_JOBS)); do
        if declare -f adapter_wait_any >/dev/null; then adapter_wait_any; else sleep 30; fi
      done

      submit_md_job "${_job_type}" "${_md_dir}" \
        "${AMBER_MD_CMD}" \
        -O \
        -i "${_md_input_file}" \
        -p "${_topology_file}" \
        -c mdin.ncrst \
        -o md.out \
        -r md.rst \
        -x md.nc >"${_md_dir}/.jid_tmp"
      _jid=$(cat "${_md_dir}/.jid_tmp")
      rm -f "${_md_dir}/.jid_tmp"

      _job_ids+=("${_jid}")
      _submitted_md_dirs+=("${_md_dir}")
    done
    ;;
  *)
    msg_error "Unknown engine: ${_engine}"
    return 1
    ;;
  esac

  while true; do
    _running=$(current_running_jobs "${_job_ids[@]}")

    for _md_dir in "${_submitted_md_dirs[@]}"; do
      if [[ -f "${_md_dir}/.job_exit_code" ]]; then
        _ec=$(cat "${_md_dir}/.job_exit_code")
        if ((_ec != 0)); then
          msg_error "MD job in ${_md_dir} failed with exit code ${_ec}."
          exit 1
        fi
      fi
    done

    if ((_running == 0)); then
      break
    fi

    if declare -f adapter_wait_any >/dev/null; then adapter_wait_any; else sleep 30; fi
  done

  # Final fail-fast verification: Ensure all jobs completed properly without silent termination
  for _md_dir in "${_submitted_md_dirs[@]}"; do
    if [[ ! -f "${_md_dir}/.job_exit_code" ]]; then
      msg_error "MD job in ${_md_dir} terminated abruptly without writing an exit code (e.g., OOM or Walltime limit)."
      exit 1
    fi
    _ec=$(cat "${_md_dir}/.job_exit_code")
    if ((_ec != 0)); then
      msg_error "MD job in ${_md_dir} failed with exit code ${_ec}."
      exit 1
    fi
  done

  msg_success "Completed [Action]: Run Parallel MD (cycle_$(printf "%03d" "${_cycle_id}"))"
}

compute_collective_variables() {
  local -r _cycle_id="$1"
  local -r _compute_cv_script_file="$2"
  local -r _work_root_dir="$3"
  local -r _topology_file="$4"
  local _cycle_dir=""
  local -a _md_dirs=()
  local -i _running_jobs=0
  local _md_dir=""
  local _traj_file=""

  printf -v _cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"

  if [[ -f "${_cycle_dir}/md_001/cv.txt" ]]; then
    msg_info "Skipping [Action]: Compute Collective Variables - cv.txt already exists."
    return 0
  fi

  msg_info "Starting [Action]: Compute Collective Variables (cycle_$(printf "%03d" "${_cycle_id}"))"

  require_dir "${_cycle_dir}"
  require_file "${_compute_cv_script_file}"

  mapfile -t _md_dirs < <(compgen -G "${_cycle_dir}/md_*" || true)

  if ((${#_md_dirs[@]} == 0)); then
    msg_error "No md directories found in ${_cycle_dir}"
    return 1
  fi

  _running_jobs=0

  for _md_dir in "${_md_dirs[@]}"; do
    _traj_file=""

    if [[ -f "${_md_dir}/md.xtc" ]]; then
      _traj_file="${_md_dir}/md.xtc"
      _structure_file="${_md_dir}/md.tpr"
    elif [[ -f "${_md_dir}/md.nc" ]]; then
      _traj_file="${_md_dir}/md.nc"
      _structure_file="${_md_dir}/md.ncrst"
    else
      msg_error "Trajectory file not found in ${_md_dir}"
      return 1
    fi

    "${_compute_cv_script_file}" "${_traj_file}" "${_topology_file}" "${_structure_file}" "${_md_dir}/cv.txt" "${_cycle_id}" &
    ((_running_jobs++)) || true

    if ((_running_jobs >= MAX_PARALLEL)); then
      wait -n || {
        msg_error "Failed [Action]: A background job in Compute CV terminated with an error."
        return 1
      }
      ((_running_jobs--)) || true
    fi
  done

  wait || {
    msg_error "Failed [Action]: A background job in Compute CV terminated with an error."
    return 1
  }

  for _md_dir in "${_md_dirs[@]}"; do
    require_file "${_md_dir}/cv.txt"
  done

  msg_success "Completed [Action]: Compute Collective Variables (cycle_$(printf "%03d" "${_cycle_id}"))"
}

aggregate_cv_results() {
  local -r _cycle_id="$1"
  local -r _work_root_dir="$2"
  local _cycle_dir=""
  local _analysis_dir=""
  local _output_file=""
  local -a _cv_files=()
  local -i _prev_cycle=0
  local _prev_file=""

  printf -v _cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"
  _analysis_dir="${_cycle_dir}/analysis"
  _output_file="${_analysis_dir}/cv_all.txt"

  if [[ -s "${_output_file}" ]]; then
    msg_info "Skipping [Action]: Aggregate CV Results - Target file already exists."
    return 0
  fi

  msg_info "Starting [Action]: Aggregate CV Results (cycle_$(printf "%03d" "${_cycle_id}"))"

  require_dir "${_cycle_dir}"
  mkdir -p "${_analysis_dir}"

  mapfile -t _cv_files < <(compgen -G "${_cycle_dir}/md_*/cv.txt" || true)

  if ((${#_cv_files[@]} == 0)); then
    msg_error "No cv.txt files found in ${_cycle_dir}"
    return 1
  fi

  _prev_cycle=$((_cycle_id - 1))

  if ((_prev_cycle > 0)); then
    printf -v _prev_file "%s/cycle_%03d/analysis/cv_all.txt" \
      "${_work_root_dir}" "${_prev_cycle}"

    if [[ -f "${_prev_file}" ]]; then
      cat "${_prev_file}" >"${_output_file}"
    else
      : >"${_output_file}"
    fi
  else
    : >"${_output_file}"
  fi

  cat "${_cv_files[@]}" >>"${_output_file}"

  require_file "${_output_file}"

  if [[ ! -s "${_output_file}" ]]; then
    msg_error "Aggregate failed: output file is empty"
    return 1
  fi

  msg_success "Completed [Action]: Aggregate CV Results (cycle_$(printf "%03d" "${_cycle_id}"))"
}

select_next_seeds() {
  local -r _cycle_id="$1"
  local -r _engine="$2"
  local -r _work_root_dir="$3"
  local -r _topology_file="$4"
  local _cycle_dir=""
  local _analysis_dir=""
  local _input_file=""
  local _output_file=""
  local _select_seeds_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/select_seeds.py"
  local _traj_file_name=""
  local _topology_file_name=""
  local _procheck_dir="${AA_OFLOOD_ROOT}/libexec/external/PROCHECK/procheck"
  local _monitor_script="${AA_OFLOOD_ROOT}/libexec/scripts/sampling_monitor.py"

  printf -v _cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"

  _analysis_dir="${_cycle_dir}/analysis"
  _input_file="${_analysis_dir}/cv_all.txt"
  _output_file="${_analysis_dir}/selected_seeds.txt"
  if [[ -s "${_output_file}" ]]; then
    msg_info "Skipping [Action]: Next Seed Selection - Target file already exists."
  else
    msg_info "Starting [Action]: Next Seed Selection (cycle_$(printf "%03d" "${_cycle_id}"))"

    require_dir "${_analysis_dir}"
    require_file "${_input_file}"
    require_file "${_select_seeds_script_file}"

    if [[ "${_engine}" == "gromacs" ]]; then
      _traj_file_name="md.xtc"
      _topology_file_name="mdin.gro"
    else
      _traj_file_name="md.nc"
      _topology_file_name="${_topology_file}"
    fi

    if ! "${PYTHON3}" "${_select_seeds_script_file}" \
      --input-file "${_input_file}" \
      --output-file "${_output_file}" \
      --work-root-dir "${_work_root_dir}" \
      --topology-file "${_topology_file_name}" \
      --traj-file-name "${_traj_file_name}" \
      --procheck-dir "${_procheck_dir}" \
      --eps "${CLUSTER_EPS}" \
      --min-samples "${CLUSTER_MIN_SAMPLES}" \
      --n-seeds "${SAMPLING_SEEDS_PER_CYCLE:-100}" \
      --g-factor-threshold "${G_FACTOR}" \
      --max-workers "${MAX_PARALLEL}" \
      --n-cv "${N_CV:-2}"; then
      msg_error "Failed [Action]: Next Seed Selection (execution error)"
      return 1
    fi

    require_file "${_output_file}"

    msg_success "Completed [Action]: Next Seed Selection (cycle_$(printf "%03d" "${_cycle_id}"))"
  fi

  if [[ "${PLOT_MODE:-false}" == "true" ]]; then
    if [[ -f "${_monitor_script}" ]]; then
      local _dist_pdf="${_analysis_dir}/sampling_distribution.pdf"
      local _conv_pdf="${_analysis_dir}/sampling_convergence.pdf"
      
      if [[ -f "${_dist_pdf}" && -f "${_conv_pdf}" ]]; then
        msg_info "Skipping [Action]: Generate Sampling Monitor Plots - Target files already exist."
      else
        msg_info "Starting [Action]: Generate Sampling Monitor Plots"
        "${PYTHON3}" "${_monitor_script}" \
          --work-root-dir "${_work_root_dir}" \
          --current-cycle "${_cycle_id}" \
          --output-dir "${_analysis_dir}" \
          --grid-bins "${GRID_BINS}" \
          --xlabel "${CV_X_LABEL}" \
          --ylabel "${CV_Y_LABEL}" || return 1
        msg_success "Completed [Action]: Generate Sampling Monitor Plots"
      fi
    fi
  fi
}

oflood_main() {
  local _initial_seed_dir=""
  local _engine=""
  local _md_input_file=""
  local _topology_file=""
  local _frame_dt_ps=""
  local _compute_cv_script_file=""
  local _max_cycles=""
  local _work_root_dir=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --seed-dir)
      _initial_seed_dir="$2"
      shift 2
      ;;
    --engine)
      _engine="$2"
      shift 2
      ;;
    --param-file)
      _md_input_file="$2"
      shift 2
      ;;
    --top-file)
      _topology_file="$2"
      shift 2
      ;;
    --frame-dt-ps)
      _frame_dt_ps="$2"
      shift 2
      ;;
    --cv-script)
      _compute_cv_script_file="$2"
      shift 2
      ;;
    --max-cycles)
      _max_cycles="$2"
      shift 2
      ;;
    --work-root)
      _work_root_dir="$2"
      shift 2
      ;;
    *)
      msg_error "Unknown parameter passed: $1"
      exit 1
      ;;
    esac
  done

  if [[ -z "${_initial_seed_dir}" || -z "${_engine}" || -z "${_md_input_file}" || -z "${_topology_file}" || -z "${_frame_dt_ps}" || -z "${_compute_cv_script_file}" || -z "${_max_cycles}" || -z "${_work_root_dir}" ]]; then
    printf "Usage:\n  %s --seed-dir <dir> --engine <engine> --param-file <file> --top-file <file> \\\n" "$0" >&2
    printf "     --frame-dt-ps <dt> --cv-script <script> --max-cycles <N> --work-root <dir>\n" >&2
    exit 1
  fi

  local -i _cycle_id=1
  local _cycle_dir=""

  require_dir "${_initial_seed_dir}"
  require_file "${_md_input_file}"
  require_file "${_topology_file}"
  require_file "${_compute_cv_script_file}"

  mkdir -p "${_work_root_dir}"

  while ((_cycle_id <= _max_cycles)); do
    msg_info "Starting Cycle $(printf "%03d" "${_cycle_id}")"

    printf -v _cycle_dir "%s/cycle_%03d" "${_work_root_dir}" "${_cycle_id}"

    prepare_seeds "${_cycle_id}" "${_initial_seed_dir}" "${_engine}" "${_frame_dt_ps}" "${_work_root_dir}"
    run_parallel_md "${_cycle_id}" "${_engine}" "${_md_input_file}" "${_topology_file}" "${_work_root_dir}" "sampling"
    compute_collective_variables "${_cycle_id}" "${_compute_cv_script_file}" "${_work_root_dir}" "${_topology_file}"
    aggregate_cv_results "${_cycle_id}" "${_work_root_dir}"
    select_next_seeds "${_cycle_id}" "${_engine}" "${_work_root_dir}" "${_topology_file}"

    msg_success "Completed Cycle $(printf "%03d" "${_cycle_id}")"
    ((_cycle_id++)) || true
  done

  msg_success "Workflow Finished Successfully"
}
