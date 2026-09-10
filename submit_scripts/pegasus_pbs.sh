#!/usr/bin/env bash
# File: pegasus_pbs.sh
# Description: HPC adapter for PBS / NEC NQSV (Pegasus cluster)
# shellcheck disable=SC2034
# The Pegasus cluster, operated by the University of Tsukuba

# 1. MD SIMULATION (Stage 5,6)
MAX_CONCURRENT_JOBS=10 # Maximum parallel MD jobs submitted to PBS at once

HPC_GROUP="group1"
HPC_QUEUE="gpu"
HPC_NCPUS=48
WALLTIME_MD="02:00:00"

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

  local _jid
  local _tmp_script
  _tmp_script=$(mktemp "${_work_dir}/pbs_md_XXXXXX.sh")

  cat >"${_tmp_script}" <<EOF
#!/usr/bin/env bash
#PBS -A ${HPC_GROUP}
#PBS -q ${HPC_QUEUE}
#PBS -l elapstim_req=${WALLTIME_MD}
#PBS -v OMP_NUM_THREADS=${HPC_NCPUS}
#PBS -N oflood_${_job_type}_$(basename "${_work_dir}")
#PBS -o ${_work_dir}/pbs.o
#PBS -e ${_work_dir}/pbs.e

export GROMACS_DIR="${GROMACS_DIR}"
export AMBER_DIR="${AMBER_DIR}"

mkdir -p "${_work_dir}"
source "${SUBMIT_SCRIPT_FILE}"
setup_env_md

cd "${_work_dir}" || exit 1
${_cmd[*]} > "${_work_dir}/mdrun.log" 2>&1
echo \$? > "${_work_dir}/.job_exit_code"
EOF
  _jid=$(qsub "${_tmp_script}" | grep -oE '[0-9]+')
  rm -f "${_tmp_script}"
  echo "${_jid}"
}

# current_running_jobs: count how many PBS jobs are currently running from a list of job IDs
current_running_jobs() {
  local -a _check_jids=("$@")
  local -i _count=0
  local _jid
  local _all_jobs

  _all_jobs=$(qstat 2>/dev/null || true)

  for _jid in "${_check_jids[@]}"; do
    [[ -z "${_jid}" ]] && continue
    if grep -qw "${_jid}" <<<"${_all_jobs}"; then
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

  local _jid
  local _tmp_script
  _tmp_script=$(mktemp "${_work_dir}/pbs_ai_XXXXXX.sh")

  cat >"${_tmp_script}" <<EOF
#!/usr/bin/env bash
#PBS -A ${HPC_GROUP}
#PBS -q ${HPC_QUEUE}
#PBS -l elapstim_req=01:00:00
#PBS -v OMP_NUM_THREADS=${HPC_NCPUS}
#PBS -N oflood_ai_$(basename "${_work_dir}")
#PBS -o ${_work_dir}/pbs.o
#PBS -e ${_work_dir}/pbs.e

export COLABFOLD_DIR="${COLABFOLD_DIR}"

mkdir -p "${_work_dir}"
source "${SUBMIT_SCRIPT_FILE}"
setup_env_ai

cd "${_work_dir}" || exit 1
${_cmd[*]}
EOF
  _jid=$(qsub "${_tmp_script}" | grep -oE '[0-9]+')
  rm -f "${_tmp_script}"
  echo "${_jid}"
}
