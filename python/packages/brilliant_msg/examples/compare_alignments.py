"""
Compare mag/accel alignment matrices across Halo units (and across solver runs).

Answers: "is the alignment matrix a per-unit constant that could be shipped as a
default?" It separates two sources of matrix difference:

  * SOLVER spread — the alignment solver is non-convex with a random refine, so
    re-solving the SAME samples with different seeds gives slightly different
    matrices. This is noise, not unit variation.
  * UNIT spread — the geodesic angle between different units' matrices.

If unit spread >> solver spread, the residual misalignment is genuinely
per-unit and a shipped default only gets you so far. If they are comparable,
the units agree to within solver noise and a default is worthwhile.

Inputs are `label=path` pairs. `path` is either:
  * a *_samples.json from imu_calibrate.py --samples-out  (re-solved K times), or
  * a mag_calibration.json                                 (matrix used as-is).

Usage:
    uv run python packages/brilliant_msg/examples/compare_alignments.py \
        "Halo 08=halo08_samples.json" "Halo 50=halo50_samples.json"
"""
import argparse
import json
import sys

import numpy as np

from brilliant_msg.calibration import compute_calibration

# nominal coarse in-plane relationship the two dies are mounted at (~+90° about Z)
RZ90 = np.array([[0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])


def geodesic_deg(a, b):
    """Angle of the rotation that takes a to b (deg) — the natural distance
    between two rotation matrices."""
    r = np.asarray(a) @ np.asarray(b).T
    cos = (np.trace(r) - 1.0) / 2.0
    return float(np.degrees(np.arccos(np.clip(cos, -1.0, 1.0))))


def axis_angle(r):
    r = np.asarray(r)
    angle = np.degrees(np.arccos(np.clip((np.trace(r) - 1.0) / 2.0, -1.0, 1.0)))
    ax = np.array([r[2, 1] - r[1, 2], r[0, 2] - r[2, 0], r[1, 0] - r[0, 1]])
    n = np.linalg.norm(ax)
    ax = ax / n if n > 1e-9 else np.array([0.0, 0.0, 1.0])
    return ax, float(angle)


def solve_many(samples, seeds):
    """Re-solve the alignment from raw samples for each seed; return list of R."""
    mats = []
    for s in seeds:
        cal, _ = compute_calibration(
            samples["compass"], samples["accel"],
            ref_mag=tuple(samples["ref_compass"]),
            ref_accel=tuple(samples["ref_accel"]),
            ref_heading_deg=samples.get("ref_heading_deg", 0.0),
            seed=s)
        mats.append(np.array(cal.matrix))
    return mats


def representative(mats):
    """Medoid matrix (the one with least total geodesic distance to the rest)."""
    best, best_cost = mats[0], float("inf")
    for m in mats:
        cost = sum(geodesic_deg(m, o) for o in mats)
        if cost < best_cost:
            best, best_cost = m, cost
    return best


def max_pairwise(mats):
    return max((geodesic_deg(mats[i], mats[j])
                for i in range(len(mats)) for j in range(i + 1, len(mats))),
               default=0.0)


def main():
    ap = argparse.ArgumentParser(description="Compare alignment matrices across units.")
    ap.add_argument("inputs", nargs="+", help='label=path (samples.json or calibration.json)')
    ap.add_argument("--seeds", type=int, default=6, help="re-solves per samples file")
    args = ap.parse_args()

    units = []  # (label, representative_matrix, solver_spread_or_None)
    for item in args.inputs:
        if "=" not in item:
            sys.exit(f"expected label=path, got: {item}")
        label, path = item.split("=", 1)
        with open(path) as f:
            d = json.load(f)
        if "compass" in d and "accel" in d:
            mats = solve_many(d, range(args.seeds))
            rep = representative(mats)
            spread = max_pairwise(mats)
            print(f"[{label}] re-solved {args.seeds}× from {len(d['compass'])} samples "
                  f"→ solver spread (max pairwise) = {spread:.2f}°")
            units.append((label, rep, spread))
        elif "matrix" in d:
            print(f"[{label}] matrix loaded from calibration JSON (no samples → "
                  f"cannot measure solver spread)")
            units.append((label, np.array(d["matrix"]), None))
        else:
            sys.exit(f"{path}: not a samples or calibration JSON")

    print("\nPer-unit alignment (residual after removing the nominal +90°-about-Z mount):")
    for label, m, _ in units:
        ax, ang = axis_angle(m)
        resid = geodesic_deg(m, RZ90)
        ax_r, ang_r = axis_angle(RZ90.T @ m)
        print(f"  {label:10s}  full angle {ang:6.2f}°   "
              f"residual-vs-nominal {resid:5.2f}° about ({ax_r[0]:+.2f},{ax_r[1]:+.2f},{ax_r[2]:+.2f})")

    if len(units) >= 2:
        print("\nUnit-to-unit geodesic distance:")
        worst_solver = max((s for _, _, s in units if s is not None), default=None)
        for i in range(len(units)):
            for j in range(i + 1, len(units)):
                d = geodesic_deg(units[i][1], units[j][1])
                print(f"  {units[i][0]} ↔ {units[j][0]}: {d:.2f}°")
        if worst_solver is not None:
            print(f"\nWorst within-unit solver spread: {worst_solver:.2f}°")
            print("Interpretation: unit-to-unit distances that are close to (or below) "
                  "the solver spread mean the units agree to within solver noise → a "
                  "shipped default matrix is worthwhile. Distances several× larger mean "
                  "the residual is genuinely per-unit.")


if __name__ == "__main__":
    main()
