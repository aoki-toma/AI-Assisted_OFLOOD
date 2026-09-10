#!/usr/bin/env bash
# File: setup.sh
# Description: Environment setup for AI-Assisted OFLOOD
# Note: Conda environment, AI tools (e.g. ColabFold), GROMACS, and AMBER
#       should be installed manually by the user.

set -euo pipefail

msg_info() {
  printf "\e[34m[INFO]    %s\e[0m\n" "$*"
}

msg_success() {
  printf "\e[32m[SUCCESS] %s\e[0m\n" "$*"
}

msg_error() {
  printf "\e[31m[ERROR]   %s\e[0m\n" "$*" >&2
}

main() {
  local -r _aa_oflood_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  local -r _external_dir="${_aa_oflood_root}/libexec/external"

  mkdir -p "${_external_dir}"

  # Install PROCHECK
  local -r _procheck_dir="${_external_dir}/PROCHECK"
  local -r _procheck_src_dir="${_procheck_dir}/procheck"
  msg_info "Setting up PROCHECK..."
  if [[ -f "${_procheck_src_dir}/procheck.scr" ]]; then
    msg_info "PROCHECK is already installed at ${_procheck_src_dir}."
  else
    msg_info "Cloning PROCHECK repository..."
    rm -rf "${_procheck_dir}"
    git clone https://github.com/RomanLas/PROCHECK.git "${_procheck_dir}"
    
    msg_info "Extracting PROCHECK source code..."
    (
      cd "${_procheck_dir}" || exit 1
      tar -xzf procheck.tar.gz
    )

    msg_info "Compiling PROCHECK with gfortran..."
    (
      cd "${_procheck_src_dir}" || exit 1
      if ! command -v gfortran &>/dev/null; then
        msg_error "gfortran not found. PROCHECK compilation failed."
        exit 1
      fi
      # PROCHECK is a legacy software and uses old C standards (implicit int, etc.).
      # Modern clang (e.g., on macOS) treats these warnings as errors.
      # We override CC to pass relaxed flags, with fallbacks for older Linux compilers.
      make F77=gfortran CC="cc -Wno-implicit-int -Wno-implicit-function-declaration" \
        || make F77=gfortran \
        || ./procomp.scr \
        || {
        msg_error "Failed to compile PROCHECK."
        exit 1
      }
    )
    msg_success "PROCHECK setup completed."
  fi

  msg_info "Note: Conda environment, AI structure predictors, GROMACS, and AMBER are not installed by this script. Please install them manually and ensure they are in your PATH."
  msg_success "Environment setup finished successfully! Ready to run AI-Assisted OFLOOD."
}

main "$@"
