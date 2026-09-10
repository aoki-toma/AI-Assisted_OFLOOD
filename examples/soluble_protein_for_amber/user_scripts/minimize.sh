#!/usr/bin/env bash
# File: minimize.sh
# Description: Run Amber energy minimization for relaxation

set -euo pipefail

_crd_file="${1}"
_target_top_file="${2}"
_output_dir="${3}"

_base=$(basename "${_crd_file}" .inpcrd)
_temp_dir="${_output_dir}/temp_${_base}"
_output_rst_file="${_output_dir}/${_base}.ncrst"

mkdir -p "${_output_dir}"
mkdir -p "${_temp_dir}"

# Generate mdin files using heredoc
cat <<EOF >"${_temp_dir}/min1_restraint.mdin"
Stage 1: Minimization with restraints on heavy atoms
 &cntrl
  imin=1, maxcyc=1000, ncyc=500,
  ntpr=50, ntwx=0,
  cut=8.0, ntb=1,
  ntc=1, ntf=1,
  ntr=1, restraint_wt=50.0,
  restraintmask='!@H=',
 /
EOF

cat <<EOF >"${_temp_dir}/min2_full.mdin"
Stage 2: Full minimization
 &cntrl
  imin=1, maxcyc=2000, ncyc=1000,
  ntpr=50, ntwx=0,
  cut=8.0, ntb=1,
  ntc=1, ntf=1,
 /
EOF

# Step 1: Restrained EM
sander -O \
  -i "${_temp_dir}/min1_restraint.mdin" \
  -p "${_target_top_file}" \
  -c "${_crd_file}" \
  -ref "${_crd_file}" \
  -o "${_temp_dir}/min1.out" \
  -r "${_temp_dir}/min1.ncrst" \
  -inf "${_temp_dir}/min1.info" >/dev/null 2>&1

# Step 2: Full EM
sander -O \
  -i "${_temp_dir}/min2_full.mdin" \
  -p "${_target_top_file}" \
  -c "${_temp_dir}/min1.ncrst" \
  -o "${_temp_dir}/min2.out" \
  -r "${_temp_dir}/min2.ncrst" \
  -inf "${_temp_dir}/min2.info" >/dev/null 2>&1

# Collect results
cp "${_temp_dir}/min2.ncrst" "${_output_rst_file}"

rm -rf "${_temp_dir}"
