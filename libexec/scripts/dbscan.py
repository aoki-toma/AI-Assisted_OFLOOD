#!/usr/bin/env python3
# File: dbscan.py
# Description: Performs DBSCAN clustering on CV data to identify outlier seeds.

import argparse
import logging
import sys
from pathlib import Path
import numpy as np

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] [%(asctime)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logger = logging.getLogger(__name__)


def cluster_data(input_file: Path, output_dir: Path, eps: float, min_samples: int, n_cv: int):
    if not input_file.is_file():
        logger.error(f"Input file not found: {input_file}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        all_data = np.loadtxt(input_file)
    except Exception as e:
        logger.error(f"Failed to load data from {input_file}: {e}")
        sys.exit(1)

    outliers_file = output_dir / "outliers.txt"
    clustered_file = output_dir / "clustered_points.txt"

    if all_data.size == 0:
        open(outliers_file, "w").close()
        open(clustered_file, "w").close()
        return

    if all_data.ndim == 1:
        all_data = all_data.reshape(1, -1)

    if all_data.shape[1] < n_cv + 3:
        logger.error(
            f"Input data must have at least {n_cv + 3} columns, got {all_data.shape[1]}"
        )
        sys.exit(1)

    try:
        from sklearn.cluster import DBSCAN
    except ImportError:
        logger.error("scikit-learn is not installed.")
        sys.exit(1)

    features = all_data[:, :n_cv]
    db = DBSCAN(eps=eps, min_samples=min_samples, n_jobs=-1).fit(features)
    labels = db.labels_

    outliers = all_data[labels == -1]
    clustered_points = all_data[labels != -1]

    try:
        cv_fmt = " ".join(["%.5f"] * n_cv)
        meta_fmt = " ".join(["%d"] * 3)
        row_fmt = f"{cv_fmt} {meta_fmt}"
        np.savetxt(outliers_file, outliers, fmt=row_fmt)
        np.savetxt(clustered_file, clustered_points, fmt=row_fmt)
    except Exception as e:
        logger.error(f"Failed to save results to {output_dir}: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-file", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--eps", type=float, default=0.5)
    parser.add_argument("--min-samples", dest="min_samples", type=int, default=5)
    parser.add_argument("--n-cv", type=int, default=2)
    args = parser.parse_args()

    cluster_data(args.input_file, args.output_dir, args.eps, args.min_samples, args.n_cv)


if __name__ == "__main__":
    main()
