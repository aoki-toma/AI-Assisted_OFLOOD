#!/usr/bin/env bash
# File: compute_cv.sh
# Stage 5/6: Collective Variable Calculation
set -euo pipefail

# [USER SETTINGS]
# Arguments passed by run_oflood.sh as positional arguments:
_traj_file="${1}"
_top_file="${2}"
_structure_file="${3}"
_out_file="${4}"
_cycle_id="${5}"
