#!/usr/bin/env python3
# File: extract_params.py
# Description: Extracts MD parameters (e.g. frame_dt_ps) from engine configuration files.

import argparse
import sys
import re
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] [%(asctime)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%S%z")
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True, choices=["gromacs", "amber"])
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--key", required=True, choices=["frame_dt_ps"])
    args = parser.parse_args()

    if not args.file.is_file():
        logger.error(f"Input file not found: {args.file}")
        sys.exit(1)

    try:
        content = args.file.read_text(encoding="utf-8")
    except Exception as e:
        logger.error(f"Failed to read {args.file}: {e}")
        sys.exit(1)

    params = {}
    if args.engine == "gromacs":
        for raw_line in content.splitlines():
            line = raw_line.split(";", 1)[0].strip()
            if "=" in line:
                key, _, val = line.partition("=")
                params[key.strip()] = val.strip()

        try:
            dt = float(params.get("dt", "0.002"))
            freq_str = params.get("nstxout-compressed") or params.get("nstxout", "")
            value = dt * float(freq_str) if freq_str else 0.1
        except Exception:
            value = 0.1

    elif args.engine == "amber":
        cleaned = "\n".join(line for line in content.splitlines() if not line.lstrip().startswith("!"))
        for match in re.finditer(r"(\w+)\s*=\s*([^\s,/&]+)", cleaned):
            params[match.group(1).lower()] = match.group(2)

        try:
            dt = float(params.get("dt", "0.002"))
            ntwx_str = params.get("ntwx", "")
            value = dt * float(ntwx_str) if ntwx_str else 0.1
        except Exception:
            value = 0.1

    print(f"{value:.6f}")

if __name__ == "__main__":
    main()
