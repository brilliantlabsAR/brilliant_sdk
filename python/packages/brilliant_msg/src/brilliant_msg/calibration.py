"""
Magnetometer calibration for tilt-compensated heading.

Three corrections are needed for a usable worn/tilted compass, and they are
independent:

  1. Hard-iron: a per-axis offset that re-centres the magnetometer sphere.
  2. Mag/accel alignment: a rotation that expresses the magnetometer vector in
     the accelerometer's body frame. The QMC6308 magnetometer and BMA580
     accelerometer are separate parts at different orientations, so their axes
     do not coincide; tilt compensation requires them in one frame. Solving it
     needs orientation coverage (a full tumble).
  3. Heading offset: a scalar that fixes the absolute heading zero. The tumble
     constrains tilt but not "north", so this comes from one known-heading,
     level reference sample.

`MagCalibration` holds all three and applies them at runtime (pure Python, no
numpy). The offline solver (`compute_calibration`) needs numpy and is intended
for a calibration tool, not the runtime path — see examples/imu_calibrate.py.

Inputs/outputs use the host frame produced by RxIMU (+X right, +Y forward,
+Z up), so a calibration composes with the shipped imu.lua remap.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from typing import Tuple

Vec3 = Tuple[float, float, float]
Mat3 = Tuple[Vec3, Vec3, Vec3]

_IDENTITY: Mat3 = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))

# Default Halo mag->accel alignment, used when no per-unit matrix is supplied.
# The QMC6308 (mag) and BMA580 (accel) dies are mounted at a fixed nominal
# orientation offset (~90 deg about Z plus a small tilt) that is consistent
# across units, so a fresh MagCalibration ships with it and tilt compensation
# works before any per-unit calibration; identity leaves a residual tilt error.
# A per-unit tumble or a loaded calibration JSON overrides it. Halo-specific:
# for Frame or other hardware pass matrix=_IDENTITY (or that unit's own matrix).
HALO_DEFAULT_ALIGNMENT: Mat3 = (
    (-0.005078, -0.998944, -0.045656),
    (0.999975, -0.005296, 0.004647),
    (-0.004884, -0.045631, 0.998946),
)


@dataclass
class MagCalibration:
    """Hard-iron offset + mag->accel alignment rotation + heading offset, host frame.

    apply():   m_corrected = matrix @ (m_raw + offset)
    heading(): tilt-compensated heading of m_corrected using accel, plus heading_offset_deg
    """
    offset: Vec3 = (0.0, 0.0, 0.0)
    matrix: Mat3 = HALO_DEFAULT_ALIGNMENT
    heading_offset_deg: float = 0.0
    field_uT: float = 0.0   # mean field magnitude (raw units) for optional uT scaling

    def apply(self, mag: Vec3) -> Vec3:
        cx = mag[0] + self.offset[0]
        cy = mag[1] + self.offset[1]
        cz = mag[2] + self.offset[2]
        r = self.matrix
        return (
            r[0][0] * cx + r[0][1] * cy + r[0][2] * cz,
            r[1][0] * cx + r[1][1] * cy + r[1][2] * cz,
            r[2][0] * cx + r[2][1] * cy + r[2][2] * cz,
        )

    def heading(self, mag: Vec3, accel: Vec3, declination: float = 0.0) -> float:
        """Tilt-compensated true heading (deg, 0-360) from a raw host-frame
        magnetometer + accelerometer sample. Applies hard-iron, alignment,
        the heading offset, and (optionally) magnetic declination."""
        from .heading import tilt_compensated_heading
        m = self.apply(mag)
        h = tilt_compensated_heading(m[0], m[1], m[2], accel[0], accel[1], accel[2])
        return (h + self.heading_offset_deg + declination) % 360.0

    def to_dict(self) -> dict:
        return {
            "offset": list(self.offset),
            "matrix": [list(row) for row in self.matrix],
            "heading_offset_deg": self.heading_offset_deg,
            "field_uT": self.field_uT,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "MagCalibration":
        return cls(
            offset=tuple(d["offset"]),
            matrix=tuple(tuple(row) for row in d["matrix"]),
            heading_offset_deg=d.get("heading_offset_deg", 0.0),
            field_uT=d.get("field_uT", 0.0),
        )

    def save(self, path: str) -> None:
        with open(path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def load(cls, path: str) -> "MagCalibration":
        with open(path) as f:
            return cls.from_dict(json.load(f))


# --------------------------------------------------------------------------
# Offline solver (requires numpy). Not used on the runtime heading path.
# --------------------------------------------------------------------------

def fit_hard_iron(mag):
    """Least-squares sphere fit. Returns (offset_vec, radius).

    offset is the negative centre, so mag + offset is centred on the origin.
    """
    import numpy as np
    m = np.asarray(mag, dtype=float)
    x, y, z = m[:, 0], m[:, 1], m[:, 2]
    A = np.column_stack([2 * x, 2 * y, 2 * z, np.ones_like(x)])
    b = x * x + y * y + z * z
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    center = sol[:3]
    radius = float(np.sqrt(sol[3] + center @ center))
    return (-center[0], -center[1], -center[2]), radius


def _rot(euler):
    import numpy as np
    cx, cy, cz = np.cos(euler)
    sx, sy, sz = np.sin(euler)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rx @ Ry @ Rz


def solve_alignment(mag_centered, accel, seed: int = 0):
    """Solve the rotation that aligns the (hard-iron-corrected) magnetometer to
    the accelerometer body frame, by making the magnetometer-vs-gravity angle
    constant across orientations.

    Returns (matrix3x3_as_tuples, dip_std_before_deg, dip_std_after_deg).

    The absolute heading zero is not constrained by the tumble; it is set
    separately via MagCalibration.heading_offset_deg from a known reference.
    """
    import numpy as np
    m = np.asarray(mag_centered, dtype=float)   # hard-iron corrected
    a = np.asarray(accel, dtype=float)
    n = m / np.linalg.norm(m, axis=1, keepdims=True)
    a = a / np.linalg.norm(a, axis=1, keepdims=True)
    rng = np.random.default_rng(seed)

    # near-level samples: the horizontal field they trace must remain a
    # constant-radius circle. A rotation that tilts that circle into an ellipse
    # (folding the vertical field in) corrupts the heading even though the dip
    # stays constant, so this term selects the correct rotation.
    level = a[:, 2] > 0.85
    if level.sum() < 10:
        level = a[:, 2] > 0.7
    m_level = m[level] if level.sum() >= 10 else None

    def dip_std(R):
        # angle between the R-rotated magnetometer and the accelerometer
        proj = np.clip(np.sum((n @ R.T) * a, axis=1), -1.0, 1.0)
        return float(np.degrees(np.arccos(proj)).std())

    def level_circle_relstd(R):
        if m_level is None:
            return 0.0
        h = np.linalg.norm((m_level @ R.T)[:, :2], axis=1)
        return float(h.std() / max(h.mean(), 1e-9))

    def cost(e):
        R = _rot(e)
        return dip_std(R) + 60.0 * level_circle_relstd(R)

    before = dip_std(np.eye(3))
    # coarse grid, then random local refine from the best several seeds
    grid = np.deg2rad(np.arange(-180, 180, 30))
    seeds = []
    for ex in grid:
        for ey in grid:
            for ez in grid:
                seeds.append((cost((ex, ey, ez)), np.array([ex, ey, ez])))
    seeds.sort(key=lambda s: s[0])

    best_e, best_v = None, None
    for _, seed_e in seeds[:8]:
        e = seed_e.copy()
        bv = cost(e)
        step = np.deg2rad(30)
        for it in range(8000):
            cand = e + rng.uniform(-step, step, 3)
            v = cost(cand)
            if v < bv:
                e, bv = cand, v
            if it % 1000 == 999:
                step *= 0.6
        if best_v is None or bv < best_v:
            best_e, best_v = e, bv
    R = _rot(best_e)
    after = dip_std(R)
    matrix = tuple(tuple(float(v) for v in row) for row in R)
    return matrix, before, after


def solve_heading_offset(cal: MagCalibration, ref_mag, ref_accel,
                         known_heading_deg: float) -> float:
    """Return the heading offset (deg) that makes `cal` report
    `known_heading_deg` for a level reference sample facing a known bearing."""
    raw = MagCalibration(offset=cal.offset, matrix=cal.matrix)  # offset=0 heading
    measured = raw.heading(ref_mag, ref_accel)
    return (known_heading_deg - measured) % 360.0


def compute_calibration(compass, accel, seed: int = 0,
                        ref_mag=None, ref_accel=None, ref_heading_deg: float = 0.0):
    """Full calibration from host-frame tumble samples.

    compass, accel: sequences of (x, y, z) host-frame samples covering many
    orientations (a full tumble). Optionally pass one level reference sample
    (ref_mag, ref_accel) facing a known bearing (ref_heading_deg) to also solve
    the absolute heading offset. Returns (MagCalibration, info_dict).
    """
    import numpy as np
    offset, radius = fit_hard_iron(compass)
    m = np.asarray(compass, dtype=float) + np.asarray(offset)
    a = np.asarray(accel, dtype=float)
    matrix, before, after = solve_alignment(m, a, seed=seed)
    cal = MagCalibration(offset=tuple(float(o) for o in offset),
                         matrix=matrix, field_uT=radius)
    if ref_mag is not None and ref_accel is not None:
        cal.heading_offset_deg = solve_heading_offset(cal, ref_mag, ref_accel, ref_heading_deg)

    # validation gate: at level, the aligned heading must match the
    # (already-correct) uncorrected level heading up to one constant offset.
    # A large residual means the alignment corrupted the azimuth.
    R = np.array(matrix)
    an = a / np.linalg.norm(a, axis=1, keepdims=True)
    level = an[:, 2] > 0.9
    level_residual = 0.0
    if level.sum() >= 10:
        nn = m[level] / np.linalg.norm(m[level], axis=1, keepdims=True)
        hu = np.degrees(np.arctan2(nn[:, 1], nn[:, 0]))
        bm = m[level] @ R.T
        ha = np.degrees(np.arctan2(bm[:, 1], bm[:, 0]))
        diff = np.radians(ha - hu)
        off = math.atan2(np.sin(diff).mean(), np.cos(diff).mean())
        res = (ha - hu - math.degrees(off) + 180) % 360 - 180
        level_residual = float(res.std())
    info = {"hard_iron_radius": radius,
            "dip_std_before_deg": before,
            "dip_std_after_deg": after,
            "worn_error_estimate_deg": after,
            "level_heading_residual_deg": level_residual}
    return cal, info
