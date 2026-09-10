#!/usr/bin/env python3
# File: sampling_monitor.py
# Description: Generates plots to monitor sampling convergence over OFLOOD cycles.

import argparse
import logging
import sys
from pathlib import Path
import numpy as np
import matplotlib
import matplotlib.ticker as ticker

matplotlib.use("Agg")
import matplotlib.pyplot as plt

matplotlib.rcParams["font.family"] = "sans-serif"
matplotlib.rcParams["font.sans-serif"] = [
    "Arial",
    "Helvetica",
    "DejaVu Sans",
    "sans-serif",
]
matplotlib.rcParams["mathtext.fontset"] = "custom"
matplotlib.rcParams["mathtext.rm"] = "Arial"
matplotlib.rcParams["mathtext.it"] = "Arial:italic"
matplotlib.rcParams["mathtext.bf"] = "Arial:bold"

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] [%(asctime)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root-dir", type=Path, required=True)
    parser.add_argument("--current-cycle", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--grid-bins", type=int, default=100)
    parser.add_argument("--xlabel", type=str, default="CV$_{1}$")
    parser.add_argument("--ylabel", type=str, default="CV$_{2}$")
    args = parser.parse_args()

    analysis_dir = args.output_dir
    analysis_dir.mkdir(parents=True, exist_ok=True)

    cv_all_file = analysis_dir / "cv_all.txt"
    if cv_all_file.is_file():
        try:
            data = np.loadtxt(cv_all_file)
            if data.size > 0 and data.ndim == 2:
                fig, ax = plt.subplots()

                clustered_file = analysis_dir / "clustered_points.txt"
                if clustered_file.is_file():
                    c_data = np.loadtxt(clustered_file)
                    if c_data.size > 0:
                        ax.scatter(
                            c_data[:, 0],
                            c_data[:, 1],
                            s=1,
                            alpha=0.5,
                            c="blue",
                            label="Clustered",
                            rasterized=True,
                        )

                outliers_file = analysis_dir / "outliers.txt"
                if outliers_file.is_file():
                    o_data = np.loadtxt(outliers_file)
                    if o_data.size > 0:
                        ax.scatter(
                            o_data[:, 0],
                            o_data[:, 1],
                            s=20,
                            c="red",
                            alpha=0.8,
                            label="Outliers",
                            rasterized=True,
                        )

                seeds_file = analysis_dir / "selected_seeds.txt"
                if seeds_file.is_file():
                    s_data = np.loadtxt(seeds_file)
                    if s_data.size > 0:
                        if s_data.ndim == 1:
                            s_data = s_data.reshape(1, -1)
                        ax.scatter(
                            s_data[:, 0],
                            s_data[:, 1],
                            s=80,
                            marker="*",
                            c="gold",
                            edgecolors="black",
                            label="Seeds",
                            rasterized=True,
                        )

                ax.set_title(f"Sampling Distribution (Cycle {args.current_cycle})")
                ax.set_xlabel(args.xlabel)
                ax.set_ylabel(args.ylabel)
                ax.legend()
                fig.savefig(
                    analysis_dir / "sampling_distribution.pdf",
                    dpi=300,
                    bbox_inches="tight",
                )
                plt.close(fig)
        except Exception as e:
            logger.error(f"Failed to generate sampling distribution plot: {e}")
            sys.exit(1)

    global_range = None
    latest_file = (
        args.work_root_dir
        / f"cycle_{args.current_cycle:03d}"
        / "analysis"
        / "cv_all.txt"
    )
    if latest_file.is_file():
        try:
            latest_data = np.loadtxt(latest_file)
            if latest_data.size > 0 and latest_data.ndim == 2:
                xmin, xmax = np.min(latest_data[:, 0]), np.max(latest_data[:, 0])
                ymin, ymax = np.min(latest_data[:, 1]), np.max(latest_data[:, 1])
                global_range = [[xmin, xmax], [ymin, ymax]]
        except Exception as e:
            logger.warning(f"Failed to determine global range from {latest_file}: {e}")

    cycle_numbers = []
    occupied_counts = []

    for cycle in range(1, args.current_cycle + 1):
        cycle_file = (
            args.work_root_dir / f"cycle_{cycle:03d}" / "analysis" / "cv_all.txt"
        )
        if cycle_file.is_file():
            try:
                cv_data = np.loadtxt(cycle_file)
                if cv_data.size > 0 and cv_data.ndim == 2:
                    kwargs = {"bins": args.grid_bins}
                    if global_range is not None:
                        kwargs["range"] = global_range

                    hist, _, _ = np.histogram2d(cv_data[:, 0], cv_data[:, 1], **kwargs)
                    count = np.count_nonzero(hist)
                    cycle_numbers.append(cycle)
                    occupied_counts.append(count)
            except Exception as e:
                logger.error(f"Failed to process {cycle_file}: {e}")
                sys.exit(1)

    if cycle_numbers:
        try:
            fig, ax = plt.subplots()
            ax.plot(
                cycle_numbers, occupied_counts, marker="o", linestyle="-", color="blue"
            )
            ax.set_yscale("log")
            ax.yaxis.set_major_locator(
                ticker.LogLocator(base=10.0, subs=(1.0, 2.0, 5.0))
            )
            formatter = ticker.ScalarFormatter()
            formatter.set_scientific(False)
            ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))
            ax.yaxis.set_major_formatter(formatter)
            ax.yaxis.set_minor_formatter(ticker.NullFormatter())
            ax.set_xlabel("OFLOOD Cycle Number")
            ax.set_ylabel("Number of Occupied Grid Cells (Log scale)")
            ax.set_title("Sampling Convergence")
            ax.grid(True, linestyle="--", alpha=0.6)

            fig.savefig(
                analysis_dir / "sampling_convergence.pdf", dpi=300, bbox_inches="tight"
            )
            plt.close(fig)
        except Exception as e:
            logger.error(f"Failed to generate convergence plot: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
