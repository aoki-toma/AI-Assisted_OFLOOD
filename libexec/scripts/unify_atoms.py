#!/usr/bin/env python3
# File: unify_atoms.py
# Description: Standardizes atom counts across MD systems by unifying solvent molecules.

import argparse
import logging
import random
import shutil
import sys
from collections import defaultdict
from pathlib import Path
import numpy as np
import MDAnalysis as mda
import parmed as pmd

RANDOM_SEED = 42
SUPPORTED_COORD_EXT = {".gro", ".inpcrd", ".ncrst"}
SUPPORTED_TOP_EXT = {".top", ".prmtop"}

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] [%(asctime)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logger = logging.getLogger(__name__)
logging.getLogger("MDAnalysis").setLevel(logging.WARNING)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--coord-dir", type=Path, required=True)
    parser.add_argument("--top-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    out_coord_dir = args.output_dir / "coordinates"
    out_top_dir = args.output_dir / "topology"
    out_coord_dir.mkdir(parents=True, exist_ok=True)
    out_top_dir.mkdir(parents=True, exist_ok=True)

    random.seed(RANDOM_SEED)

    try:
        pairs = []
        for c_file in sorted(args.coord_dir.iterdir()):
            if c_file.name.startswith("."):
                continue
            if c_file.suffix.lower() not in SUPPORTED_COORD_EXT:
                continue
            for ext in SUPPORTED_TOP_EXT:
                t_file = args.top_dir / f"{c_file.stem}{ext}"
                if t_file.exists():
                    pairs.append((c_file, t_file))
                    break
            else:
                logger.warning(f"No matching topology found for: {c_file.name}")

        if not pairs:
            logger.error("No valid coordinate/topology pairs found.")
            sys.exit(1)

        parsed_systems = []
        solute_resnames = set()

        for c_file, t_file in pairs:
            if c_file.suffix.lower() == ".gro":
                universe = mda.Universe(str(c_file))
            else:
                universe = mda.Universe(str(t_file), str(c_file))

            for sel in ("protein", "nucleic"):
                try:
                    solute_resnames.update(universe.select_atoms(sel).residues.resnames)
                except Exception:
                    pass
            parsed_systems.append(
                {"universe": universe, "c_file": c_file, "t_file": t_file}
            )

        reference_system = min(
            parsed_systems, key=lambda s: s["universe"].atoms.n_atoms
        )
        ref_universe = reference_system["universe"]

        target_composition = {}
        counts = defaultdict(int)
        for resname in ref_universe.residues.resnames:
            counts[resname] += 1
        for resname, count in counts.items():
            if resname not in solute_resnames:
                target_composition[resname] = count

        master_top_file = (
            out_top_dir / f"master_topology{reference_system['t_file'].suffix}"
        )
        shutil.copy(reference_system["t_file"], master_top_file)

        # For AMBER format, rebuild target_composition using ParmEd to avoid
        # the 1-atom discrepancy caused by MDAnalysis silently skipping certain
        # atom types (e.g. virtual sites / extra points / zero-mass atoms) that
        # ParmEd correctly includes.  solute_resnames is still derived from
        # MDAnalysis (it's just a set of strings, no index translation needed).
        target_composition_amber: dict = {}
        if reference_system["c_file"].suffix.lower() != ".gro":
            _ref_pmd = pmd.load_file(
                str(reference_system["t_file"]),
                str(reference_system["c_file"]),
            )
            for _res in _ref_pmd.residues:
                if _res.name not in solute_resnames:
                    target_composition_amber[_res.name] = (
                        target_composition_amber.get(_res.name, 0) + 1
                    )

        for system in parsed_systems:
            c_suffix = system["c_file"].suffix.lower()

            if c_suffix == ".gro":
                # ── GROMACS path: MDAnalysis handles selection and writing ──
                universe = system["universe"]
                non_solute_resnames = set(universe.residues.resnames) - solute_resnames

                is_valid = True
                for resname in non_solute_resnames:
                    res_count = np.sum(universe.residues.resnames == resname)
                    target_count = target_composition.get(resname, 0)
                    if res_count < target_count:
                        is_valid = False
                        break

                if not is_valid:
                    continue

                keep_mask = np.zeros(len(universe.residues), dtype=bool)
                keep_mask[np.isin(universe.residues.resnames, list(solute_resnames))] = True

                for resname in non_solute_resnames:
                    res_idx = np.where(universe.residues.resnames == resname)[0]
                    target_count = target_composition.get(resname, 0)
                    if len(res_idx) > target_count:
                        selected_idx = sorted(random.sample(list(res_idx), target_count))
                        keep_mask[selected_idx] = True
                    else:
                        keep_mask[res_idx] = True

                final_residues = universe.residues[keep_mask]
                out_path = out_coord_dir / system["c_file"].name
                new_universe = mda.Merge(final_residues.atoms)
                new_universe.dimensions = universe.dimensions
                new_universe.atoms.write(str(out_path))

            else:
                # ── AMBER path: ParmEd handles everything independently ──
                out_path = out_coord_dir / system["c_file"].name

                pmd_struct = pmd.load_file(
                    str(system["t_file"]), str(system["c_file"])
                )

                pmd_non_solute: dict = {}
                for res in pmd_struct.residues:
                    if res.name not in solute_resnames:
                        pmd_non_solute.setdefault(res.name, []).append(res)

                is_valid = True
                for resname, res_list in pmd_non_solute.items():
                    if len(res_list) < target_composition_amber.get(resname, 0):
                        is_valid = False
                        break

                if not is_valid:
                    continue

                # Build strict 0-based index mapping to bypass any ParmEd atom.idx bugs
                atom_to_idx = {id(atom): i for i, atom in enumerate(pmd_struct.atoms)}
                keep_atom_idx: list = []

                for res in pmd_struct.residues:
                    if res.name in solute_resnames:
                        for atom in res.atoms:
                            keep_atom_idx.append(atom_to_idx[id(atom)])

                for resname, res_list in pmd_non_solute.items():
                    target_count = target_composition_amber.get(resname, 0)
                    if len(res_list) > target_count:
                        selected = sorted(
                            random.sample(res_list, target_count),
                            key=lambda r: r.idx if hasattr(r, 'idx') else 0,
                        )
                    else:
                        selected = res_list
                    for res in selected:
                        for atom in res.atoms:
                            keep_atom_idx.append(atom_to_idx[id(atom)])

                if len(keep_atom_idx) == len(pmd_struct.atoms):
                    shutil.copy(system["c_file"], out_path)
                else:
                    pmd_subset = pmd_struct[sorted(keep_atom_idx)]
                    pmd_subset.save(str(out_path), format="rst7", overwrite=True)


    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
