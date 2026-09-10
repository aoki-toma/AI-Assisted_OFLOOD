#!/usr/bin/env bash
# File: prepare_md.sh
# Description: Build membrane system using packmol-memgen and convert to GROMACS format

set -euo pipefail

_pdb_file="${1}"
_top_dir="${2}"
_crd_dir="${3}"
_base=$(basename "${_pdb_file}" .pdb)
_temp_dir="${_crd_dir}/temp_${_base}"

rm -rf "${_temp_dir}"
mkdir -p "${_temp_dir}"

cd "${_temp_dir}" || exit 1
packmol-memgen --pdb "${_pdb_file}" -o "${_temp_dir}/packmol_lipid" \
  --packlog "${_temp_dir}/packmol_log" \
  --random \
  --movebadrandom \
  --pdb2pqr_pH 7.0 \
  --n_ter in \
  --solvents WAT \
  --salt_c Na+ \
  --salt_a Cl- \
  --lipids POPC \
  --dims 120 120 120 \
  --parametrize \
  --ffprot ff14SB \
  --ffwat tip3p \
  --fflip lipid21 \
  --engine sander \
  --tolerance 2.0 \
  --minimize >"${_temp_dir}/packmol.log" 2>&1

# Convert Amber outputs of packmol-memgen to GROMACS format using ParmEd
_top_file="${_top_dir}/${_base}.top"
_crd_file="${_crd_dir}/${_base}.gro"
"${PYTHON3}" -c "
import parmed as pmd
parm = pmd.load_file('${_temp_dir}/packmol_lipid_lipid.top', '${_temp_dir}/packmol_lipid_lipid.crd')
parm.save('${_top_file}', format='gromacs')
parm.save('${_crd_file}')
" >"${_temp_dir}/parmed.log" 2>&1

rm -rf "${_temp_dir}"
