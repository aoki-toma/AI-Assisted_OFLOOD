#!/usr/bin/env bash
# File: minimize.sh
# Description: Run GROMACS energy minimization for relaxation

set -euo pipefail

_crd_file="${1}"
_target_top_file="${2}"
_output_dir="${3}"
_base=$(basename "${_crd_file}" .gro)
_temp_dir="${_output_dir}/temp_${_base}"

rm -rf "${_temp_dir}"
mkdir -p "${_output_dir}"
mkdir -p "${_temp_dir}"

cat <<EOF >"${_temp_dir}/minim.mdp"
integrator  = steep
emtol       = 1000.0
emstep      = 0.01
nsteps      = 50000
nstlist         = 1
cutoff-scheme   = Verlet
ns_type         = grid
coulombtype     = PME
rcoulomb        = 1.2
rvdw            = 1.2
pbc             = xyz
EOF

# 1. Run grompp
gmx_mpi grompp \
  -f "${_temp_dir}/minim.mdp" \
  -c "${_crd_file}" \
  -p "${_target_top_file}" \
  -o "${_temp_dir}/em.tpr" \
  -po "${_temp_dir}/em.mdp" \
  -maxwarn 1 >"${_temp_dir}/grompp.log" 2>&1

# 2. Run mdrun
gmx_mpi mdrun \
  -s "${_temp_dir}/em.tpr" \
  -c "${_output_dir}/${_base}.gro" \
  -deffnm "${_temp_dir}/em" \
  -ntomp 1 \
  >"${_temp_dir}/mdrun.log" 2>&1

rm -rf "${_temp_dir}"
