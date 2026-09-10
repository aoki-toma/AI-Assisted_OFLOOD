#!/usr/bin/env bash
# File: para_conf.sh
# Description: Configuration parameters for soluble protein simulation (Ribose Binding Protein example)
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
MAX_SAMPLING_CYCLES="2"      # 75 (paper)
SAMPLING_SEEDS_PER_CYCLE="2" # 100 (paper)

MAX_PRODUCTION_CYCLES="1"      # 7 (paper)
PRODUCTION_SEEDS_PER_CYCLE="2" # 30 (paper)

N_CV="2"

# 7. Seed Clustering Parameters
CLUSTER_EPS="0.6"
CLUSTER_MIN_SAMPLES="15"
G_FACTOR="-0.82"

# 8. MSM / FEL Analysis Parameters
MSM_LAGTIME="150"
MSM_N_CLUSTERS="150"
MSM_LAG_LIST="1 10 100 500 1000 1500 2000"
MSM_CK_STATES="3"

# 9. Plotting and Visualization Parameters
CV_X_LABEL="Hinge angle [deg]"
CV_Y_LABEL="Twist angle [deg]"
GRID_BINS="20"
