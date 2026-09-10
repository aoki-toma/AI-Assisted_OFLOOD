#!/usr/bin/env bash
# File: minimize.sh
# Stage 4: Energy Minimization
set -euo pipefail

# [USER SETTINGS]
# Arguments passed by pipeline.sh:
_crd_file="$1"
_target_top_file="$2"
_output_dir="$3"
