#!/usr/bin/env bash
# File: prepare_md.sh
# Description: Build MD system using Amber tleap and convert to GROMACS format

set -euo pipefail

_pdb_file="${1}"
_top_dir="${2}"
_crd_dir="${3}"
_base=$(basename "${_pdb_file}" .pdb)
_temp_dir="${_crd_dir}/temp_${_base}"

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
saveAmberParm mol "${_temp_dir}/output.prmtop" "${_temp_dir}/output.inpcrd"
quit
EOF

cd "${_temp_dir}" || exit 1
tleap -f "${_leap_in_file}" >"${_temp_dir}/leap.log" 2>&1

# Convert Amber format to GROMACS format using ParmEd
_top_file="${_top_dir}/${_base}.top"
_crd_file="${_crd_dir}/${_base}.gro"
"${PYTHON3}" -c "
import parmed as pmd
parm = pmd.load_file('${_temp_dir}/output.prmtop', '${_temp_dir}/output.inpcrd')
parm.save('${_top_file}', format='gromacs')
parm.save('${_crd_file}')
" >"${_temp_dir}/parmed.log" 2>&1

rm -rf "${_temp_dir}"
