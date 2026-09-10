#!/usr/bin/env bash
# File: para_conf.sh
# Description: All user-facing configuration parameters for an AI-Assisted OFLOOD project.
# shellcheck disable=SC2034

# 1. Simulation Engine
ENGINE="gromacs" # gromacs or amber
GMX_CMD="gmx_mpi"

# 2. Stage Providers
BUILD_MD_SYSTEM_FILE="${PROJECT_DIR}/user_scripts/prepare_md.sh"
MINIMIZE_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/minimize.sh"
COMPUTE_CV_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/compute_cv.sh"

# 3. HPC Adapter
SUBMIT_SCRIPT_FILE="${AA_OFLOOD_ROOT}/submit_scripts/template.sh"

# 4. Parallelism
MAX_PARALLEL="8"

# 5. MD Input Files
SAMPLING_PARAM_FILE="${PROJECT_DIR}/mdp/sampling.mdp"
PRODUCTION_PARAM_FILE="${PROJECT_DIR}/mdp/production.mdp"

# 6. OFLOOD Method Parameters
MAX_SAMPLING_CYCLES="5"
SAMPLING_SEEDS_PER_CYCLE="50"

MAX_PRODUCTION_CYCLES="2"
PRODUCTION_SEEDS_PER_CYCLE="30"

N_CV="2"

# 7. Seed Clustering Parameters
CLUSTER_EPS="0.6"
CLUSTER_MIN_SAMPLES="15"
G_FACTOR=-0.50

# 8. MSM / FEL Analysis Parameters
MSM_LAGTIME="100"
MSM_N_CLUSTERS="100"
MSM_LAG_LIST="1 10 100 500 1000 1500 2000"
MSM_CK_STATES="4"

# 9. Plotting and Visualization Parameters
CV_X_LABEL="CV 1"
CV_Y_LABEL="CV 2"
GRID_BINS="10"
