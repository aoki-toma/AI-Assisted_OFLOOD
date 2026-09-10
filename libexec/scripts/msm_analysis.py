#!/usr/bin/env python3
# File: msm_analysis.py
# Description: Builds Markov State Models and computes free energy landscapes.

import argparse
import logging
import pickle
import sys
from pathlib import Path
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] [%(asctime)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logger = logging.getLogger(__name__)

RANDOM_SEED = 42

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

try:
    import deeptime
    import deeptime.plots as dplt
    from deeptime.clustering import KMeans
    from deeptime.markov import TransitionCountEstimator
    from deeptime.markov.msm import MaximumLikelihoodMSM
except ModuleNotFoundError as e:
    logger.error(f"deeptime or dependent packages are not installed: {e}")
    sys.exit(1)


def load_data(args):
    if not args.input_cv_files:
        logger.error("--input-cv-files is required.")
        sys.exit(1)

    data_list = []
    for p in args.input_cv_files:
        if not p.exists() or p.stat().st_size == 0:
            continue
        try:
            data = np.loadtxt(p)
            if data.ndim == 1:
                data = data.reshape(1, -1)
            data_list.append(data[:, : args.n_cv])
        except Exception:
            continue

    if not data_list:
        logger.error("No valid input CV files loaded.")
        sys.exit(1)
    return data_list


def run_check_mode(args, data_list):
    np.random.seed(RANDOM_SEED)

    try:
        all_data = np.vstack(data_list)
        clustering = KMeans(
            n_clusters=args.n_clusters, max_iter=1000, fixed_seed=RANDOM_SEED
        ).fit(all_data)
        dtrajs = [clustering.transform(d) for d in data_list]
    except Exception as e:
        logger.error(f"KMeans clustering failed: {e}")
        sys.exit(1)

    dtrajs_file = args.output_dir / "dtrajs.npy"
    clust_file = args.output_dir / "clustering_model.pkl"

    try:
        np.save(dtrajs_file, np.array(dtrajs, dtype=object), allow_pickle=True)
        with open(clust_file, "wb") as f:
            pickle.dump(clustering, f)
    except Exception as e:
        logger.error(f"Failed to save clustering outputs: {e}")
        sys.exit(1)

    models = []
    for lag in args.lags:
        try:
            counts = (
                TransitionCountEstimator(lagtime=lag, count_mode="sliding")
                .fit(dtrajs)
                .fetch_model()
            )
            models.append(MaximumLikelihoodMSM().fit(counts).fetch_model())
        except Exception as e:
            logger.warning(f"Failed to fit model at lag={lag}: {e}")

    if not models:
        logger.error("Failed to estimate any transition count model.")
        sys.exit(1)

    its_plot_file = args.output_dir / "its_plot.pdf"
    try:
        its_data = deeptime.util.validation.implied_timescales(models, n_its=5)
        fig, ax = plt.subplots(figsize=(6, 5))
        dplt.plot_implied_timescales(its_data, ax=ax, marker="o")
        ax.set_yscale("log")
        ax.set_xlabel("lag time [steps]")
        ax.set_ylabel("Implied Timescales [steps]")
        plt.tight_layout()
        fig.savefig(its_plot_file, dpi=300)
        plt.close(fig)
    except AttributeError:
        its = np.array([m.timescales()[:5] for m in models])
        fig, ax = plt.subplots(figsize=(6, 5))
        for i in range(its.shape[1]):
            ax.plot(args.lags[: len(models)], its[:, i], marker="o")
        ax.set_yscale("log")
        ax.set_xlabel("lag time [steps]")
        ax.set_ylabel("Implied Timescales [steps]")
        plt.tight_layout()
        fig.savefig(its_plot_file, dpi=300)
        plt.close(fig)
    except Exception as e:
        logger.error(f"Failed to generate ITS plot: {e}")
        sys.exit(1)


def run_production_mode(args, data_list):
    dtrajs_file = args.output_dir / "dtrajs.npy"
    clust_file = args.output_dir / "clustering_model.pkl"
    msm_file = args.output_dir / "msm_model.pkl"
    ck_plot_file = args.output_dir / "ck_test.pdf"
    fel_plot_file = args.output_dir / "fel_landscape.pdf"
    pmf_txt_file = args.output_dir / "pmf_landscape.txt"

    if not dtrajs_file.exists() or not clust_file.exists():
        logger.error("Intermediate clustering files not found. Run 'check' mode first.")
        sys.exit(1)

    try:
        loaded_dtrajs = np.load(dtrajs_file, allow_pickle=True)
        dtrajs = [np.array(d, dtype=int) for d in loaded_dtrajs]
        with open(clust_file, "rb") as f:
            clustering = pickle.load(f)
    except Exception as e:
        logger.error(f"Failed to load clustering models: {e}")
        sys.exit(1)

    try:
        counts = (
            TransitionCountEstimator(lagtime=args.lag_time, count_mode="sliding")
            .fit(dtrajs)
            .fetch_model()
        )
        msm_model = MaximumLikelihoodMSM().fit(counts).fetch_model()
        with open(msm_file, "wb") as f:
            pickle.dump(msm_model, f)
    except Exception as e:
        logger.error(f"Failed to fit MSM model: {e}")
        sys.exit(1)

    ck_models = []
    for k in range(1, 11):
        ck_lag = args.lag_time * k
        try:
            ck_counts = (
                TransitionCountEstimator(lagtime=ck_lag, count_mode="sliding")
                .fit(dtrajs)
                .fetch_model()
            )
            ck_models.append(MaximumLikelihoodMSM().fit(ck_counts).fetch_model())
        except Exception:
            pass

    if ck_models:
        try:
            ck_test = msm_model.ck_test(
                models=ck_models, n_metastable_sets=args.ck_states
            )
            plt.figure(figsize=(10, 8))
            dplt.plot_ck_test(ck_test)
            plt.tight_layout()
            plt.savefig(ck_plot_file, dpi=300)
            plt.close()
        except Exception as e:
            logger.warning(f"Failed to perform CK-test: {e}")

    try:
        all_data = np.vstack(data_list)
        model_obj = msm_model.models[0] if hasattr(msm_model, "models") else msm_model
        weight_list = model_obj.compute_trajectory_weights(dtrajs)
        weights = np.concatenate(weight_list)

        if len(all_data) != len(weights):
            logger.error(
                f"Data length mismatch: data={len(all_data)}, weights={len(weights)}"
            )
            sys.exit(1)

        hist, xedges, yedges = np.histogram2d(
            all_data[:, 0], all_data[:, 1], bins=100, weights=weights, density=True
        )

        hist = hist.T
        with np.errstate(divide="ignore"):
            free_energy = -np.log(hist)
        free_energy = free_energy - np.nanmin(free_energy)

        X, Y = np.meshgrid(
            xedges[:-1] + (xedges[1] - xedges[0]) / 2,
            yedges[:-1] + (yedges[1] - yedges[0]) / 2,
        )

        try:
            with open(pmf_txt_file, "w") as f:
                f.write("# X_CV1 Y_CV2 FreeEnergy(kT)\n")
                for i in range(X.shape[0]):
                    for j in range(X.shape[1]):
                        val = (
                            np.nan if np.isinf(free_energy[i, j]) else free_energy[i, j]
                        )
                        f.write(f"{X[i, j]:.6f} {Y[i, j]:.6f} {val:.6f}\n")
        except Exception as e:
            logger.error(f"Failed to write {pmf_txt_file}: {e}")

        fig, ax = plt.subplots(figsize=(6, 5))

        levels = np.linspace(0, 10, 50)
        contour = ax.contourf(X, Y, free_energy, levels=levels, cmap="jet")

        cbar = fig.colorbar(contour, ax=ax)
        cbar.set_ticks(np.arange(0, 11, 1))

        ax.set_xlabel(args.cv_labels[0] if len(args.cv_labels) > 0 else "CV 1")
        ax.set_ylabel(args.cv_labels[1] if len(args.cv_labels) > 1 else "CV 2")

        plt.tight_layout()
        fig.savefig(fel_plot_file, dpi=300)
        plt.close(fig)

    except Exception as e:
        logger.error(f"Failed to generate reweighted FEL plot: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["check", "run"], required=True)
    parser.add_argument("--input-cv-files", type=Path, nargs="+")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--n-clusters", type=int, default=100)
    parser.add_argument("--lag-time", type=int, default=100)
    parser.add_argument("--n-cv", type=int, default=2)
    parser.add_argument("--ck-states", type=int, default=6)
    parser.add_argument("--cv-labels", type=str, nargs="+", default=["CV 1", "CV 2"])
    parser.add_argument(
        "--lags", type=int, nargs="+", default=[1, 10, 100, 500, 1000, 1500, 2000]
    )
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)

    data_list = load_data(args)

    if args.mode == "check":
        run_check_mode(args, data_list)
    elif args.mode == "run":
        run_production_mode(args, data_list)


if __name__ == "__main__":
    main()

