#!/usr/bin/env python3
# File: generate_seeds.py
# Description: Selects production MD seeds from aggregated CV data uniformly across a grid.

import argparse
import sys
import random
from pathlib import Path
import numpy as np
import logging

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] [%(asctime)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%S%z")
logger = logging.getLogger(__name__)

RANDOM_SEED = 42

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-file", type=Path, required=True)
    parser.add_argument("--output-file", type=Path, required=True)
    parser.add_argument("--n-seeds", type=int, required=True)
    parser.add_argument("--n-cv", type=int, default=2)
    args = parser.parse_args()

    random.seed(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)

    if not args.input_file.is_file():
        logger.error(f"Input file not found: {args.input_file}")
        sys.exit(1)

    try:
        data = np.loadtxt(args.input_file)
    except Exception as e:
        logger.error(f"Failed to load data from {args.input_file}: {e}")
        sys.exit(1)

    n_cv = args.n_cv
    if data.size == 0 or data.ndim != 2 or data.shape[1] < n_cv + 3:
        logger.error(f"Invalid data format. Expected at least {n_cv + 3} columns and >0 rows.")
        sys.exit(1)

    target_seed_count = args.n_seeds
    cvs = data[:, :n_cv]
    cv_min = cvs.min(axis=0)
    cv_max = cvs.max(axis=0)
    cv_range = np.where(cv_max - cv_min > 0, cv_max - cv_min, 1.0)

    grid_resolution = 1
    selected_indices = []

    while True:
        grid_indices = np.clip(
            ((cvs - cv_min) / cv_range * grid_resolution).astype(int),
            0, grid_resolution - 1
        )

        occupied_cells = {}
        for i in range(len(data)):
            key = tuple(grid_indices[i])
            occupied_cells.setdefault(key, []).append(i)

        if len(occupied_cells) >= target_seed_count or grid_resolution >= 1000:
            for indices in occupied_cells.values():
                selected_indices.append(random.choice(indices))
            break
        
        grid_resolution += 1

    if len(selected_indices) > target_seed_count:
        random.shuffle(selected_indices)
        selected_indices = selected_indices[:target_seed_count]
    elif len(selected_indices) < target_seed_count:
        remaining = list(set(range(len(data))) - set(selected_indices))
        supplement_count = min(target_seed_count - len(selected_indices), len(remaining))
        selected_indices.extend(random.sample(remaining, supplement_count))

    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        with open(args.output_file, "w", encoding="utf-8") as f:
            cv_header = " ".join(f"cv{j+1}" for j in range(n_cv))
            f.write(f"# {cv_header} cycle md_id frame\n")
            for idx in selected_indices:
                row = data[idx]
                cv_str = " ".join(f"{row[j]:.5f}" for j in range(n_cv))
                f.write(f"{cv_str} {int(row[n_cv])} {int(row[n_cv + 1])} {int(row[n_cv + 2])}\n")
    except IOError as e:
        logger.error(f"Failed to write to {args.output_file}: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
