#!/usr/bin/env bash
# File: run.sh (soluble_protein example)
# Description: Entry point for soluble protein simulation (Ribose Binding Protein example)
# shellcheck disable=SC2034
#
# User Settings
#   ./run.sh 1          # Run Stage 1 (AI modeling)
#   ./run.sh 2 3 4 5    # Run Stages 2–5 in sequence
#   ./run.sh all        # Run all stages
#   ./run.sh 7          # Stage 7 check mode (implied timescales)
#   ./run.sh --mode run 7  # Stage 7 run mode (build MSM + FEL)

# User Settings
AA_OFLOOD_ROOT="/path/to/AI-Assisted_OFLOOD"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Software paths
CONDA_DIR="/path/to/conda"
AMBER_DIR="/path/to/amber"

# ColabFold (Stage 1 — set if using the built-in run_colabfold.sh)
COLABFOLD_DIR="/path/to/colabfold"
SEQUENCE="KDTIALVVSTLNNPFFVSLKDGAQKEADKLGYNLVVLDSQNNPAKELANVQDLTVRGTKILLINPTDSDAVGNAVKMANQANIPVITLDRQATKGEVVSHIASDNVLGGKIAGDYIAKKAGEGAKVIELQGIAGTSAARERGEGFQQAVAAHKFNVLASQPADFDRIKGLNVMQNLLTAHPDVQAVFAQNDEMALGALRALQTAGKSDVMVVGFDGTPDGEKAVNDGKLAATIAQLPDQIGAKGVETADKVLKGEKVQAKYPVDLKLVVKQ"

# Invoke the controller — do not edit below this line
source "${AA_OFLOOD_ROOT}/bin/controller.sh" "$@"
