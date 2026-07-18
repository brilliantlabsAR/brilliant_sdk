"""
Tests for brilliant_msg.calibration.

MagCalibration.apply is pure Python and always tested. The numpy solver is
tested on synthetic data with a known hard-iron + known mag/accel misalignment;
it must recover both (dip scatter -> ~0). numpy-dependent tests skip if numpy
is unavailable.
"""
import math

import pytest

from brilliant_msg import MagCalibration
from brilliant_msg.calibration import HALO_DEFAULT_ALIGNMENT, compute_calibration


class TestDefaultAlignment:
    def test_default_matrix_is_halo_alignment(self):
        # a fresh calibration ships the Halo default (not identity) so the worn
        # compass is tilt-stable before any per-unit calibration
        assert MagCalibration().matrix == HALO_DEFAULT_ALIGNMENT

    def test_default_alignment_is_a_valid_rotation(self):
        m = HALO_DEFAULT_ALIGNMENT
        # rows orthonormal: R @ R^T == I
        for i in range(3):
            for j in range(3):
                dot = sum(m[i][k] * m[j][k] for k in range(3))
                assert dot == pytest.approx(1.0 if i == j else 0.0, abs=1e-4)
        # right-handed: det == +1
        det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
               - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
               + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
        assert det == pytest.approx(1.0, abs=1e-4)


class TestApply:
    def test_identity_offset_only(self):
        # explicit identity: the class default is now the Halo alignment matrix
        cal = MagCalibration(offset=(1.0, 2.0, 3.0),
                             matrix=((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)))
        assert cal.apply((10.0, 20.0, 30.0)) == (11.0, 22.0, 33.0)

    def test_matrix_rotation(self):
        # 90 deg about z: (x,y,z) -> (-y, x, z)
        cal = MagCalibration(matrix=((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)))
        assert cal.apply((1.0, 0.0, 5.0)) == pytest.approx((0.0, 1.0, 5.0))

    def test_offset_then_matrix_order(self):
        cal = MagCalibration(offset=(1.0, 0.0, 0.0),
                             matrix=((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)))
        # (2,0,0)+offset=(3,0,0) -> rot -> (0,3,0)
        assert cal.apply((2.0, 0.0, 0.0)) == pytest.approx((0.0, 3.0, 0.0))

    def test_roundtrip_json(self, tmp_path):
        cal = MagCalibration(offset=(1.5, -2.5, 0.25),
                             matrix=((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
                             field_uT=470.0)
        p = str(tmp_path / "cal.json")
        cal.save(p)
        loaded = MagCalibration.load(p)
        assert loaded.offset == pytest.approx(cal.offset)
        assert loaded.field_uT == pytest.approx(470.0)
        assert loaded.apply((2.0, 0.0, 0.0)) == pytest.approx(cal.apply((2.0, 0.0, 0.0)))


class TestSolver:
    def _make(self, np, R_true, hard, incl_deg=64.0, n=400, seed=1):
        rng = np.random.default_rng(seed)

        def rot(e):
            cx, cy, cz = np.cos(e); sx, sy, sz = np.sin(e)
            Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
            Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
            Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
            return Rx @ Ry @ Rz

        I = math.radians(incl_deg)
        Bw = np.array([0, math.cos(I), math.sin(I)])
        gw = np.array([0, 0, 1.0])
        accel, mag = [], []
        for _ in range(n):
            D = rot(rng.uniform(-math.pi, math.pi, 3))
            accel.append((D.T @ gw) * 1000.0)
            mag.append((R_true @ (D.T @ Bw)) * 470.0 + hard)
        return mag, accel

    def test_recovers_hard_iron_and_alignment(self):
        np = pytest.importorskip("numpy")
        # a pitch/roll misalignment between mag and accel dies
        def rot(e):
            cx, cy, cz = np.cos(e); sx, sy, sz = np.sin(e)
            Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
            Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
            Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
            return Rx @ Ry @ Rz
        R_true = rot(np.deg2rad([18.0, -22.0, 0.0]))
        hard = np.array([120.0, -80.0, 60.0])
        mag, accel = self._make(np, R_true, hard)

        cal, info = compute_calibration(mag, accel)

        # hard-iron recovered (offset = -center)
        assert cal.offset == pytest.approx((-120.0, 80.0, -60.0), abs=2.0)
        # misalignment collapsed to near zero scatter
        assert info["dip_std_before_deg"] > 8.0
        assert info["dip_std_after_deg"] < 1.0

    def test_aligned_input_stays_aligned(self):
        np = pytest.importorskip("numpy")
        mag, accel = self._make(np, np.eye(3), np.zeros(3))
        cal, info = compute_calibration(mag, accel)
        # already aligned -> before is already tiny, after stays tiny
        assert info["dip_std_after_deg"] < 1.0
