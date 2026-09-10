#!/usr/bin/env bash
# File: pipeline.sh
# Description: Defines execution logic for all 7 stages of the OFLOOD pipeline.

set -euo pipefail

: "${AA_OFLOOD_ROOT:?AA_OFLOOD_ROOT is not set}"
: "${PROJECT_DIR:?PROJECT_DIR is not set}"

run_stage_1() {
  local -r _output_dir="${PROJECT_DIR}/inputs/prediction"
  local -r _predict_structures_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/run_colabfold.sh"
  local -r _prepare_structures_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/prepare_structures.sh"
  local -i _existing_files=0
  local _count=""

  mkdir -p "${_output_dir}"

  # Pattern A: Check if PDB files already exist
  _existing_files=0
  if has_glob_match "${_output_dir}" "*.pdb"; then
    _existing_files=1
  fi

  if ((_existing_files == 1)); then
    msg_info "Pattern A: Existing structures found. Skipping AI prediction."
  else
    # Pattern B: No files found, run ColabFold script
    msg_info "Pattern B: No existing structures found. Running AI prediction."
    require_file "${_predict_structures_script_file}"
    msg_info "Starting [Action]: AI Modeling (output: ${_output_dir})"

    # shellcheck source=/dev/null
    source "${_predict_structures_script_file}"
    (
      run_colabfold_main \
        --output-dir "${_output_dir}" \
        --sequence "${SEQUENCE:-}"
    )

    require_glob_match "${_output_dir}" "*.pdb"
  fi

  msg_info "Starting [Action]: PDB Normalization (target: ${_output_dir})"
  require_file "${_prepare_structures_script_file}"

  # shellcheck source=/dev/null
  source "${_prepare_structures_script_file}"
  prepare_structures_main --output-dir "${_output_dir}"

  _count=$(find "${_output_dir}" -maxdepth 1 -name "*.pdb" | wc -l | tr -d ' ')
  msg_success "Completed [Action]: Stage 1: ${_count} structure(s) ready"
}

run_stage_2() {
  local -r _input_dir="${PROJECT_DIR}/inputs/prediction"
  local -r _top_dir="${PROJECT_DIR}/outputs/prepared_systems/topology"
  local -r _crd_dir="${PROJECT_DIR}/outputs/prepared_systems/coordinates"
  local -a _pdb_files=()
  local -i _running_jobs=0
  local _pdb_file=""

  require_glob_match "${_input_dir}" "*.pdb"
  require_file "${BUILD_MD_SYSTEM_FILE}"
  mkdir -p "${_top_dir}" "${_crd_dir}"

  if has_glob_match "${_top_dir}" "*.top" || has_glob_match "${_top_dir}" "*.prmtop"; then
    if has_glob_match "${_crd_dir}" "*.gro" || has_glob_match "${_crd_dir}" "*.inpcrd"; then
      msg_info "Skipping [Action]: System Preparation (files already exist in ${_top_dir} and ${_crd_dir})"
      return 0
    fi
  fi

  mapfile -t _pdb_files < <(compgen -G "${_input_dir}/*.pdb" || true)
  msg_info "Starting [Action]: System Preparation (${#_pdb_files[@]} structures)"

  _running_jobs=0
  for _pdb_file in "${_pdb_files[@]}"; do
    "${BUILD_MD_SYSTEM_FILE}" "${_pdb_file}" "${_top_dir}" "${_crd_dir}" &
    ((_running_jobs++)) || true

    if ((_running_jobs >= MAX_PARALLEL)); then
      wait -n || {
        msg_error "Failed [Action]: A background job in System Preparation terminated with an error."
        exit 1
      }
      ((_running_jobs--)) || true
    fi
  done

  wait || {
    msg_error "Failed [Action]: A background job in System Preparation terminated with an error."
    exit 1
  }

  if has_glob_match "${_top_dir}" "*.prmtop" && has_glob_match "${_crd_dir}" "*.inpcrd"; then
    msg_success "Completed [Action]: System Preparation (Amber format)"
  elif has_glob_match "${_top_dir}" "*.top" && has_glob_match "${_crd_dir}" "*.gro"; then
    msg_success "Completed [Action]: System Preparation (GROMACS format)"
  else
    msg_error "Failed [Action]: System Preparation (inconsistent results)"
    exit 1
  fi
}

run_stage_3() {
  local -r _input_top_dir="${PROJECT_DIR}/outputs/prepared_systems/topology"
  local -r _input_crd_dir="${PROJECT_DIR}/outputs/prepared_systems/coordinates"
  local -r _output_dir="${PROJECT_DIR}/outputs/unified_systems"
  local -r _unify_atoms_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/unify_atoms.py"

  require_dir "${_input_top_dir}"
  require_dir "${_input_crd_dir}"
  require_file "${_unify_atoms_script_file}"

  if has_glob_match "${_output_dir}/coordinates" "*" &&
    (has_glob_match "${_output_dir}/topology" "*.top" || has_glob_match "${_output_dir}/topology" "*.prmtop"); then
    msg_info "Skipping [Action]: Unify Atoms (files already exist in ${_output_dir})"
    return 0
  fi

  mkdir -p "${_output_dir}"

  msg_info "Starting [Action]: Unify Atoms (standardizing molecule counts)"

  "${PYTHON3}" "${_unify_atoms_script_file}" \
    --coord-dir "${_input_crd_dir}" \
    --top-dir "${_input_top_dir}" \
    --output-dir "${_output_dir}"

  if has_glob_match "${_output_dir}/coordinates" "*" &&
    (has_glob_match "${_output_dir}/topology" "*.top" ||
      has_glob_match "${_output_dir}/topology" "*.prmtop"); then
    msg_success "Completed [Action]: Unify Atoms (output: ${_output_dir})"
  else
    msg_error "Failed [Action]: Unify Atoms (incomplete results)"
    exit 1
  fi
}

run_stage_4() {
  local -r _input_top_dir="${PROJECT_DIR}/outputs/unified_systems/topology"
  local -r _input_crd_dir="${PROJECT_DIR}/outputs/unified_systems/coordinates"
  local -r _output_dir="${PROJECT_DIR}/outputs/relaxed_systems"
  local -a _master_tops=()
  local _target_top_file=""
  local -a _crd_files=()
  local -i _running_jobs=0
  local _crd_file=""

  require_dir "${_input_crd_dir}"
  require_dir "${_input_top_dir}"
  require_file "${MINIMIZE_SCRIPT_FILE}"

  if has_glob_match "${_output_dir}" "*.gro" || has_glob_match "${_output_dir}" "*.ncrst"; then
    msg_info "Skipping [Action]: Energy Minimization (files already exist in ${_output_dir})"
    return 0
  fi

  mkdir -p "${_output_dir}"

  mapfile -t _master_tops < <(compgen -G "${_input_top_dir}/master_topology.*" || true)
  if ((${#_master_tops[@]} == 0)); then
    msg_error "Failed [Action]: Master topology not found in ${_input_top_dir}"
    exit 1
  fi
  _target_top_file="${_master_tops[0]}"

  mapfile -t _crd_files < <(
    compgen -G "${_input_crd_dir}/*.gro"    || true
    compgen -G "${_input_crd_dir}/*.inpcrd" || true
  )
  msg_info "Starting [Action]: Energy Minimization (${#_crd_files[@]} structures)"

  _running_jobs=0
  for _crd_file in "${_crd_files[@]}"; do
    "${MINIMIZE_SCRIPT_FILE}" "${_crd_file}" "${_target_top_file}" "${_output_dir}" &
    ((_running_jobs++)) || true

    if ((_running_jobs >= MAX_PARALLEL)); then
      wait -n || {
        msg_error "Failed [Action]: A background job in Energy Minimization terminated with an error."
        exit 1
      }
      ((_running_jobs--)) || true
    fi
  done

  wait || {
    msg_error "Failed [Action]: A background job in Energy Minimization terminated with an error."
    exit 1
  }

  if has_glob_match "${_output_dir}" "*.gro" || has_glob_match "${_output_dir}" "*.ncrst"; then
    msg_success "Completed [Action]: Energy Minimization"
  else
    msg_error "Failed [Action]: Energy Minimization (no minimized files found)"
    exit 1
  fi
}

run_stage_5() {
  local -r _initial_seed_dir="${PROJECT_DIR}/outputs/relaxed_systems"
  local -r _work_root_dir="${PROJECT_DIR}/outputs/oflood"
  local -r _unified_top_dir="${PROJECT_DIR}/outputs/unified_systems/topology"
  local -r _extract_params_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/extract_params.py"
  local -r _oflood_runner_script_file="${AA_OFLOOD_ROOT}/libexec/run_oflood.sh"
  local -a _master_tops=()
  local _target_top_file=""
  local _frame_dt_ps=""

  require_file "${_oflood_runner_script_file}"
  require_file "${SAMPLING_PARAM_FILE}"
  require_file "${_extract_params_script_file}"
  require_dir "${_initial_seed_dir}"

  mapfile -t _master_tops < <(compgen -G "${_unified_top_dir}/master_topology.*" || true)
  if ((${#_master_tops[@]} == 0)); then
    msg_error "Failed [Action]: Master topology not found in ${_unified_top_dir}"
    exit 1
  fi
  _target_top_file="${_master_tops[0]}"

  _frame_dt_ps=$("${PYTHON3}" "${_extract_params_script_file}" \
    --engine "${ENGINE}" \
    --file "${SAMPLING_PARAM_FILE}" \
    --key frame_dt_ps)

  msg_info "Starting [Action]: OFLOOD Method (output: ${_work_root_dir})"
  msg_info "  Input: ${SAMPLING_PARAM_FILE}, frame interval: ${_frame_dt_ps} ps"

  # shellcheck source=/dev/null
  source "${_oflood_runner_script_file}"

  oflood_main \
    --seed-dir "${_initial_seed_dir}" \
    --engine "${ENGINE}" \
    --param-file "${SAMPLING_PARAM_FILE}" \
    --top-file "${_target_top_file}" \
    --frame-dt-ps "${_frame_dt_ps}" \
    --cv-script "${COMPUTE_CV_SCRIPT_FILE}" \
    --max-cycles "${MAX_SAMPLING_CYCLES}" \
    --work-root "${_work_root_dir}"

  msg_success "Completed [Action]: OFLOOD Method"
}

run_stage_6() {
  local -r _oflood_dir="${PROJECT_DIR}/outputs/oflood"
  local -r _work_root_dir="${PROJECT_DIR}/outputs/production"
  local -r _unified_top_dir="${PROJECT_DIR}/outputs/unified_systems/topology"
  local -r _extract_params_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/extract_params.py"
  local -r _generate_seeds_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/generate_seeds.py"
  local -r _oflood_runner_script_file="${AA_OFLOOD_ROOT}/libexec/run_oflood.sh"
  local -a _oflood_cycle_dirs=()
  local _last_cycle_dir=""
  local _cv_all_file=""
  local -a _master_tops=()
  local _target_top_file=""
  local _seed_dir="${_work_root_dir}/seeds"
  local _selected_seeds_file=""
  local _sampling_frame_dt_ps=""
  local -r _extract_frames_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/extract_frames.sh"
  local _prod_frame_dt_ps=""

  require_file "${_oflood_runner_script_file}"
  require_file "${PRODUCTION_PARAM_FILE}"
  require_file "${_extract_params_script_file}"
  require_file "${_generate_seeds_script_file}"
  require_dir "${_oflood_dir}"

  mapfile -t _oflood_cycle_dirs < <(compgen -G "${_oflood_dir}/cycle_*" 2>/dev/null | sort || true)
  if ((${#_oflood_cycle_dirs[@]} == 0)); then
    msg_error "No OFLOOD cycle directories found in ${_oflood_dir}. Run Stage 5 first."
    exit 1
  fi
  _last_cycle_dir="${_oflood_cycle_dirs[-1]}"

  _cv_all_file="${_last_cycle_dir}/analysis/cv_all.txt"
  require_file "${_cv_all_file}"

  mapfile -t _master_tops < <(compgen -G "${_unified_top_dir}/master_topology.*" || true)
  if ((${#_master_tops[@]} == 0)); then
    msg_error "Failed [Action]: Master topology not found in ${_unified_top_dir}"
    exit 1
  fi
  _target_top_file="${_master_tops[0]}"

  if has_glob_match "${_seed_dir}" "*.gro" || has_glob_match "${_seed_dir}" "*.ncrst"; then
    msg_info "Skipping seed selection: Seeds already exist in ${_seed_dir}"
  else
    mkdir -p "${_seed_dir}"

    _selected_seeds_file="${_seed_dir}/selected_seeds.txt"
    msg_info "Selecting production seeds from ${_cv_all_file}"
    "${PYTHON3}" "${_generate_seeds_script_file}" \
      --input-file "${_cv_all_file}" \
      --output-file "${_selected_seeds_file}" \
      --n-seeds "${PRODUCTION_SEEDS_PER_CYCLE:-30}" \
      --n-cv "${N_CV:-2}"

    require_file "${_selected_seeds_file}"

    _sampling_frame_dt_ps=$("${PYTHON3}" "${_extract_params_script_file}" \
      --engine "${ENGINE}" \
      --file "${SAMPLING_PARAM_FILE}" \
      --key frame_dt_ps)

    # shellcheck source=/dev/null
    source "${_extract_frames_script_file}"
    extract_frames_from_seeds \
      --engine "${ENGINE}" \
      --seed-file "${_selected_seeds_file}" \
      --work-root "${_oflood_dir}" \
      --out-dir "${_seed_dir}" \
      --frame-dt-ps "${_sampling_frame_dt_ps}" \
      --is-production "true" \
      --top-file "${_target_top_file}"
  fi

  _prod_frame_dt_ps=$("${PYTHON3}" "${_extract_params_script_file}" \
    --engine "${ENGINE}" \
    --file "${PRODUCTION_PARAM_FILE}" \
    --key frame_dt_ps)

  msg_info "Starting [Action]: Production MD (seeds: ${_seed_dir}, output: ${_work_root_dir})"
  msg_info "  Input: ${PRODUCTION_PARAM_FILE}, frame interval: ${_prod_frame_dt_ps} ps"

  # shellcheck source=/dev/null
  source "${_oflood_runner_script_file}"

  oflood_main \
    --seed-dir "${_seed_dir}" \
    --engine "${ENGINE}" \
    --param-file "${PRODUCTION_PARAM_FILE}" \
    --top-file "${_target_top_file}" \
    --frame-dt-ps "${_prod_frame_dt_ps}" \
    --cv-script "${COMPUTE_CV_SCRIPT_FILE}" \
    --max-cycles "${MAX_PRODUCTION_CYCLES}" \
    --work-root "${_work_root_dir}"

  msg_success "Completed [Action]: Production MD"
}

run_stage_7() {
  local -r _mode="${1:-${MODE:-check}}" # default: check only
  local -r _production_dir="${PROJECT_DIR}/outputs/production"
  local -r _output_dir="${PROJECT_DIR}/outputs/msm_analysis"
  local -r _msm_analysis_script_file="${AA_OFLOOD_ROOT}/libexec/scripts/msm_analysis.py"
  local -a _cv_files=()
  local -a _lags=()

  require_file "${_msm_analysis_script_file}"
  mkdir -p "${_output_dir}"

  mapfile -t _cv_files < <(find "${_production_dir}" -type f -name "cv.txt" 2>/dev/null || true)

  if ((${#_cv_files[@]} == 0)); then
    msg_error "Failed [Action]: No cv.txt files found in ${_production_dir}"
    exit 1
  fi

  read -r -a _lags <<<"${MSM_LAG_LIST}"
  if ((${#_lags[@]} == 0)); then
    msg_error "MSM_LAG_LIST is empty. Define lag times in para_conf.sh."
    exit 1
  fi

  case "${_mode}" in
  check)
    msg_info "Starting [Action]: MSM Analysis — check mode (${#_cv_files[@]} CV files)"
    "${PYTHON3}" "${_msm_analysis_script_file}" \
      --mode "check" \
      --input-cv-files "${_cv_files[@]}" \
      --output-dir "${_output_dir}" \
      --n-clusters "${MSM_N_CLUSTERS}" \
      --n-cv "${N_CV:-2}" \
      --lags "${_lags[@]}"
    msg_success "Completed [Action]: MSM check — review implied timescales in ${_output_dir}"
    msg_info "Set MSM_LAGTIME in para_conf.sh and re-run Stage 7 with MODE=run"
    ;;

  run)
    msg_info "Starting [Action]: MSM Analysis — run mode (lag: ${MSM_LAGTIME})"
    "${PYTHON3}" "${_msm_analysis_script_file}" \
      --mode "run" \
      --input-cv-files "${_cv_files[@]}" \
      --output-dir "${_output_dir}" \
      --lag-time "${MSM_LAGTIME}" \
      --ck-states "${MSM_CK_STATES}" \
      --cv-labels "${CV_X_LABEL:-CV 1}" "${CV_Y_LABEL:-CV 2}"
    msg_success "Completed [Action]: Markov State Model Analysis (output: ${_output_dir})"
    ;;

  *)
    msg_error "Unknown Stage 7 mode: '${_mode}'. Use 'check' or 'run'."
    exit 1
    ;;
  esac
}

main() {
  local -r _reqstate_id="$1"
  local -r _stateno_id="$2"
  shift 2

  case "${_reqstate_id},${_stateno_id}" in
  query,all) echo "1 2 3 4 5 6 7" ;;
  query,1) echo "NAME='AI_Modeling';          DEPENDS=()" ;;
  run,1) run_stage_1 "$@" ;;
  query,2) echo "NAME='System_Preparation';   DEPENDS=(1)" ;;
  run,2) run_stage_2 "$@" ;;
  query,3) echo "NAME='Unify_Atoms';           DEPENDS=(2)" ;;
  run,3) run_stage_3 "$@" ;;
  query,4) echo "NAME='Energy_Minimization';  DEPENDS=(3)" ;;
  run,4) run_stage_4 "$@" ;;
  query,5) echo "NAME='OFLOOD_Sampling';       DEPENDS=(4)" ;;
  run,5) run_stage_5 "$@" ;;
  query,6) echo "NAME='OFLOOD_Production';     DEPENDS=(5)" ;;
  run,6) run_stage_6 "$@" ;;
  query,7) echo "NAME='MSM_Analysis';          DEPENDS=(6)" ;;
  run,7) run_stage_7 "$@" ;;
  *)
    msg_error "Unknown request: ${_reqstate_id} ${_stateno_id}"
    exit 1
    ;;
  esac
}

main "$@"
