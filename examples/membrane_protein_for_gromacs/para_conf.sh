#!/usr/bin/env bash
# File: para_conf.sh
# Description: Configuration parameters for NarK tranporter simulation
# shellcheck disable=SC2034

# 1. Simulation Engine
ENGINE="gromacs"
GMX_CMD="gmx_mpi"

# 2. Stage Providers
BUILD_MD_SYSTEM_FILE="${PROJECT_DIR}/user_scripts/prepare_md.sh"
MINIMIZE_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/minimize.sh"
COMPUTE_CV_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/compute_cv.sh"

# 3. HPC Adapter
SUBMIT_SCRIPT_FILE="${AA_OFLOOD_ROOT}/submit_scripts/local.sh"

# 4. Parallelism
MAX_PARALLEL="8"

# 5. MD Input Files
SAMPLING_PARAM_FILE="${PROJECT_DIR}/mdp/sampling.mdp"
PRODUCTION_PARAM_FILE="${PROJECT_DIR}/mdp/production.mdp"

# 6. OFLOOD Method Parameters
MAX_SAMPLING_CYCLES="2"      # 50 (paper)
SAMPLING_SEEDS_PER_CYCLE="2" # 100 (paper)

MAX_PRODUCTION_CYCLES="1"      # 7 (paper)
PRODUCTION_SEEDS_PER_CYCLE="2" # 30 (paper)

N_CV="2"

# 7. Seed Clustering Parameters
CLUSTER_EPS="0.06"
CLUSTER_MIN_SAMPLES="15"
G_FACTOR="-1.02"

# 8. MSM / FEL Analysis Parameters
MSM_LAGTIME="100"
MSM_N_CLUSTERS="100"
MSM_LAG_LIST="1 10 50 100 200 500"
MSM_CK_STATES="3"

# 9. Plotting and Visualization Parameters
CV_X_LABEL="Periplasmic gate [A]"
CV_Y_LABEL="Cytoplasmic gate [A]"
GRID_BINS="20"
