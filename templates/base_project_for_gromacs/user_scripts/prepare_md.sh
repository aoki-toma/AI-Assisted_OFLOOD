#!/usr/bin/env bash
# File: prepare_md.sh
# Stage 2: System Preparation
set -euo pipefail

# [USER SETTINGS]
# Arguments passed by pipeline.sh:
_pdb_file="${1}"
_top_dir="${2}"
_crd_dir="${3}"
