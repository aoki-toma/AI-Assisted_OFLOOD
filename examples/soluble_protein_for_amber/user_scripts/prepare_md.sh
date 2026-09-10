#!/usr/bin/env bash
# File: prepare_md.sh
# Description: Build MD system using Amber tleap

set -euo pipefail

_pdb_file="${1}"
_top_dir="${2}"
_crd_dir="${3}"
_base=$(basename "${_pdb_file}" .pdb)
_temp_dir="${_crd_dir}/temp_${_base}"

_top_file="${_top_dir}/${_base}.prmtop"
_crd_file="${_crd_dir}/${_base}.inpcrd"

rm -rf "${_temp_dir}"
mkdir -p "${_temp_dir}"
mkdir -p "${_top_dir}" "${_crd_dir}"

_leap_in_file="${_temp_dir}/leap.in"
cat <<EOF >"${_leap_in_file}"
source leaprc.protein.ff14SB
source leaprc.water.tip3p
mol = loadPdb "${_pdb_file}"
set mol box { 90 90 90 }
addIons mol Cl- 0
addIons mol Na+ 0
solvateBox mol TIP3PBOX 0.1
charge mol
saveAmberParm mol "${_top_file}" "${_crd_file}"
quit
EOF

cd "${_temp_dir}" || exit 1
tleap -f "${_leap_in_file}" >"${_temp_dir}/leap.log" 2>&1

rm -rf "${_temp_dir}"
