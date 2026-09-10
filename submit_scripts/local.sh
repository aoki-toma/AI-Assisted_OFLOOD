#!/usr/bin/env bash
# File: local.sh
# Description: Local execution adapter for AI-Assisted OFLOOD (no batch scheduler).
# shellcheck disable=SC2034

# 1. MD SIMULATION (Stage 5,6)
MAX_CONCURRENT_JOBS=1 # Maximum parallel MD jobs submitted to PBS at once

setup_env_md() {
  source "${GROMACS_DIR}/bin/GMXRC"
  # or
  source "${AMBER_DIR}/amber.sh"
}

submit_md_job() {
  local -r _job_type="$1" # "sampling" or "production"
  local -r _work_dir="$2"
  shift 2
  local -a _cmd=("$@")

  (
    set +e
    source "${SUBMIT_SCRIPT_FILE}"
    setup_env_md
    cd "${_work_dir}" || exit 1
    "${_cmd[@]}"
    echo $? >"${_work_dir}/.job_exit_code"
  ) >"${_work_dir}/mdrun.log" 2>&1 &

  echo "$!"
}

# current_running_jobs: count how many of the given PIDs are still alive.
current_running_jobs() {
  local -a _check_pids=("$@")
  local -i _count=0
  local _pid

  for _pid in "${_check_pids[@]}"; do
    [[ -z "${_pid}" ]] && continue
    if kill -0 "${_pid}" 2>/dev/null; then
      ((_count++))
    fi
  done

  echo "${_count}"
}

# 2. AI PREDICTION (Optional: Stage 1)
setup_env_ai() {
  export PATH="${COLABFOLD_DIR}/.pixi/envs/default/bin:${PATH}"
  export LD_LIBRARY_PATH="${COLABFOLD_DIR}/.pixi/envs/default/lib:${LD_LIBRARY_PATH}"

  # Workaround: Explicitly add paths for NVIDIA libraries hidden deep inside
  # Python's site-packages by pip, ensuring the OS can locate them via LD_LIBRARY_PATH.
  local _site_packages="${COLABFOLD_DIR}/.pixi/envs/default/lib/python3.12/site-packages"
  if [[ -d "${_site_packages}/nvidia" ]]; then
    local _nv_lib
    for _nv_lib in "${_site_packages}/nvidia"/*/lib; do
      export LD_LIBRARY_PATH="${_nv_lib}:${LD_LIBRARY_PATH}"
    done
  fi
}

submit_ai_job() {
  local -r _work_dir="$1"
  shift
  local -a _cmd=("$@")

  (
    set +e
    source "${SUBMIT_SCRIPT_FILE}"
    export COLABFOLD_DIR="${COLABFOLD_DIR}"
    setup_env_ai
    cd "${_work_dir}" || exit 1
    "${_cmd[@]}"
  ) >"${_work_dir}/colabfold.log" 2>&1 &

  echo "$!"
}
