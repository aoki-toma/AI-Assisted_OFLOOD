#!/usr/bin/env bash
# File: controller.sh
# Description: controller script for AI-Assisted OFLOOD pipeline

set -euo pipefail

_show_banner() {
  local _red='\e[1;31m'
  local _blue='\e[1;34m'
  local _gray='\e[1;90m'
  local _cyan='\e[0;36m'
  local _reset='\e[0m'

  printf "\n"
  printf "       ${_gray} ▄▀▄ ${_reset}\n"
  printf "       ${_gray}▀▄█▄▀${_reset}\n"
  printf "       ${_gray}  ▀  ${_reset}\n"
  printf "    ${_gray} ▄▀▄ ${_reset}  █████╗ ██╗        █████╗ ███████╗███████╗██╗███████╗████████╗███████╗██████╗ \n"
  printf "    ${_gray}▀▄█▄▀${_reset} ██╔══██╗██║       ██╔══██╗██╔════╝██╔════╝██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗\n"
  printf "    ${_gray}  ▀  ${_reset} ███████║██║ █████╗███████║███████╗███████╗██║███████╗   ██║   █████╗  ██║  ██║\n"
  printf "          ██╔══██║██║ ╚════╝██╔══██║╚════██║╚════██║██║╚════██║   ██║   ██╔══╝  ██║  ██║\n"
  printf "          ██║  ██║██║       ██║  ██║███████║███████║██║███████║   ██║   ███████╗██████╔╝\n"
  printf "          ╚═╝  ╚═╝╚═╝       ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚══════╝   ╚═╝   ╚══════╝╚═════╝ \n"
  printf "                         ${_red} ██████╗ ${_reset}███████╗██╗      ██████╗  ██████╗ ██████╗ \n"
  printf "                         ${_red}██╔═══██╗${_reset}██╔════╝██║     ██╔═══██╗██╔═══██╗██╔══██╗\n"
  printf "                         ${_red}██║   ██║${_reset}█████╗  ██║     ██║   ██║██║   ██║██║  ██║\n"
  printf "                         ${_red}██║   ██║${_reset}██╔══╝  ██║     ██║   ██║██║   ██║██║  ██║\n"
  printf "                         ${_red}╚██████╔╝${_reset}██║     ███████╗╚██████╔╝╚██████╔╝██████╔╝\n"
  printf "                         ${_red} ╚═════╝ ${_reset}╚═╝     ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ \n"
  printf "                         ${_blue}          ██████╗                 ██████╗                       ██╗  ${_reset}\n"
  printf "                         ${_blue}         ██╔═══██╗               ██╔═══██╗                      ████╗${_reset}\n"
  printf "                         ${_blue}███████████╝   ╚███████████████████╝   ╚██████████████████████████████║${_reset}\n"
  printf "                         ${_blue}╚══════════╝    ╚══════════════════╝    ╚═══════════════════════████╔═╝${_reset}\n"
  printf "                         ${_blue}                                                                ██╔═╝${_reset}\n"
  printf "                         ${_blue}                                                                ╚═╝${_reset}\n"
  printf "\n"
  printf "  ${_cyan}Please cite:${_reset}\n"
  printf "    [1] Aoki, T., & Harada, R. (2026)\n"
  printf "        Free Energy Calculation Method Based on Enhanced Sampling of\n"
  printf "        Diverse Protein Conformations Predicted by Artificial Intelligence.\n"
  printf "        J. Phys. Chem. Lett. DOI: 10.1021/acs.jpclett.6c00466\n"
  printf "\n"
  printf "    [2] Aoki, T., & Harada, R. (2026)\n"
  printf "        [coming soon] Bioinformatics.\n"
  printf "        DOI: [coming soon]\n"
  printf "\n"
}
_show_banner >&2

if [[ -z "${AA_OFLOOD_ROOT:-}" ]] || [[ -z "${PROJECT_DIR:-}" ]]; then
  printf "[ERROR] AA_OFLOOD_ROOT and PROJECT_DIR must be defined in run.sh.\n" >&2
  exit 1
fi
export AA_OFLOOD_ROOT
export PROJECT_DIR

# shellcheck source=/dev/null
if [[ -f "${AA_OFLOOD_ROOT}/libexec/utils.sh" ]]; then
  source "${AA_OFLOOD_ROOT}/libexec/utils.sh"
else
  printf "[ERROR] utils.sh not found under AA_OFLOOD_ROOT\n" >&2
  exit 1
fi

_usage() {
  printf "Usage: ./run.sh <stage> [<stage> ...] [--help | -h] [--plot] [--mode check|run]\n"
  printf "\n"
  printf "  stage : 1–7 or 'all'\n"
  printf "    1  AI_Modeling        — AI structure prediction\n"
  printf "    2  System_Preparation — Build solvated MD systems\n"
  printf "    3  Unify_Atoms        — Standardize atom counts across systems\n"
  printf "    4  Energy_Minimization\n"
  printf "    5  OFLOOD_Sampling    — OFLOOD method short-MD cycles\n"
  printf "    6  OFLOOD_Production  — Long MD from selected seeds\n"
  printf "    7  MSM_Analysis       — Free-energy landscape (deeptime)\n"
  printf "    all                   — Run stages 1–7 sequentially\n"
  printf "\n"
  printf "Flags:\n"
  printf "  -h, --help  Show this help message and exit\n"
  printf "  --plot      Skip MD and compute steps if completed; resume to generate per-cycle CV distribution plots (Stage 5/6)\n"
  printf "  --mode      Stage 7 sub-mode: 'check' (default) or 'run'\n"
  printf "\n"
  printf "Examples:\n"
  printf "  ./run.sh 1                       # Run Stage 1 only\n"
  printf "  ./run.sh 5 6                     # Run Stages 5 and 6\n"
  printf "  ./run.sh 7                       # Stage 7 check mode (implied timescales)\n"
  printf "  ./run.sh --mode run 7            # Stage 7 run mode (build MSM + FEL)\n"
  printf "  ./run.sh all                     # Run all stages\n"
}

_stages=()
_stage7_mode=""

while (($# > 0)); do
  case "$1" in
  --plot) export PLOT_MODE="true" ;;
  --mode)
    shift
    _stage7_mode="${1:?--mode requires an argument: check or run}"
    ;;
  all)
    _stages+=("all")
    _stage7_mode="${_stage7_mode:-check}"
    ;;
  [1-7]) _stages+=("$1") ;;
  -h | --help)
    _usage
    exit 0
    ;;
  *)
    msg_error "Unknown argument: '$1'"
    _usage >&2
    exit 1
    ;;
  esac
  shift
done

if ((${#_stages[@]} == 0)); then
  msg_error "No stage specified."
  _usage >&2
  exit 1
fi

if [[ ! -d "${PROJECT_DIR}" ]]; then
  msg_error "Project directory not found: ${PROJECT_DIR}"
  exit 1
fi

if [[ -f "${PROJECT_DIR}/para_conf.sh" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_DIR}/para_conf.sh"
  export SUBMIT_SCRIPT_FILE
else
  msg_error "para_conf.sh not found in ${PROJECT_DIR}"
  exit 1
fi

if [[ -z "${SUBMIT_SCRIPT_FILE:-}" ]]; then
  msg_error "SUBMIT_SCRIPT_FILE is not defined in para_conf.sh"
  exit 1
fi
if [[ ! -f "${SUBMIT_SCRIPT_FILE}" ]]; then
  msg_error "HPC adapter script not found: ${SUBMIT_SCRIPT_FILE}"
  exit 1
fi

_pipeline_script_file="${AA_OFLOOD_ROOT}/bin/pipeline.sh"
if [[ ! -f "${_pipeline_script_file}" ]]; then
  msg_error "Pipeline script not found: ${_pipeline_script_file}"
  exit 1
fi

# shellcheck source=/dev/null
source "${SUBMIT_SCRIPT_FILE}"

_expand_all_stages() {
  local _stage_output
  _stage_output=$(bash "${_pipeline_script_file}" "query" "all")
  echo "${_stage_output}"
}

if [[ " ${_stages[*]} " == *" all "* ]]; then
  if ((${#_stages[@]} > 1)); then
    msg_error "Cannot mix 'all' with specific stage numbers (e.g., '1 all' is invalid)."
    _usage >&2
    exit 1
  fi

  _all_stages_str=$(_expand_all_stages)
  _stages=()
  read -r -a _stages <<<"${_all_stages_str}"
fi

if ((${#_stages[@]} == 0)); then
  msg_error "No stages to run after expanding 'all'."
  exit 1
fi

setup_env_md

export GMX_CMD="${GMX_CMD:-gmx_mpi}"
export AMBER_MD_CMD="${AMBER_MD_CMD:-pmemd.cuda}"

if [[ "${ENGINE:-}" == "gromacs" ]]; then
  if ! command -v "${GMX_CMD}" >/dev/null 2>&1; then
    msg_error "GROMACS validation failed. '${GMX_CMD}' not found or failed to execute."
    msg_error "Please check your environment setup in ${SUBMIT_SCRIPT_FILE}"
    exit 1
  fi
elif [[ "${ENGINE:-}" == "amber" ]]; then
  if ! command -v "${AMBER_MD_CMD}" >/dev/null 2>&1; then
    msg_error "AMBER validation failed. '${AMBER_MD_CMD}' not found."
    msg_error "Please check your environment setup in ${SUBMIT_SCRIPT_FILE}"
    exit 1
  fi
else
  msg_error "ENGINE is undefined or invalid. Must be 'gromacs' or 'amber'."
  msg_error "Current value: '${ENGINE:-}'"
  exit 1
fi

if [[ -z "${CONDA_DIR:-}" ]]; then
  msg_error "CONDA_DIR is not defined in run.sh"
  exit 1
fi
if [[ ! -f "${CONDA_DIR}/etc/profile.d/conda.sh" ]]; then
  msg_error "conda.sh not found: ${CONDA_DIR}/etc/profile.d/conda.sh"
  msg_error "Please set CONDA_DIR to the root of your conda installation (e.g., /path/to/miniforge3)."
  exit 1
fi

# shellcheck source=/dev/null
source "${CONDA_DIR}/etc/profile.d/conda.sh"
conda activate AI-Assisted_OFLOOD

export PYTHON3="${CONDA_PREFIX}/bin/python3"
if [[ ! -x "${PYTHON3}" ]]; then
  msg_error "Python3 not found in conda environment: ${PYTHON3}"
  msg_error "Please ensure the conda environment 'AI-Assisted_OFLOOD' is properly installed."
  exit 1
fi

for _step in "${_stages[@]}"; do
  STEPNO="${_step}"
  msg_info "Invoking pipeline: stage ${STEPNO}"

  # shellcheck source=/dev/null
  source "${_pipeline_script_file}" "run" "${STEPNO}" "${_stage7_mode}"
  msg_success "Stage ${STEPNO} completed."
done
