"""
Tests for brilliant_msg.heading — compass heading conventions.

These guard the *math convention* (0=N, 90=E, 180=S, 270=W; +Y forward is the
0° reference; turning right increases heading) independent of the physical
device axis mapping, which is verified separately with hardware.
"""
import pytest

from brilliant_msg import (
    basic_heading,
    tilt_compensated_heading,
    apply_declination,
    degrees_to_cardinal,
)

# Sydney, Australia geomagnetic reference (approx, epoch ~2025), used only to
# exercise the declination math here. Declination is location-specific, so the
# SDK does not ship it; look up your own at
# https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml
SYDNEY_DECLINATION_DEG = 12.7      # +east; add to a magnetic heading for true heading


class TestBasicHeading:
    # host frame: +X right, +Y forward. A magnetometer reading pointing along
    # +Y means North is straight ahead -> heading 0.
    @pytest.mark.parametrize("mx, my, expected", [
        (0.0, 1.0, 0.0),     # North ahead (+Y)  -> facing North
        (-1.0, 0.0, 90.0),   # North to the left -> facing East
        (0.0, -1.0, 180.0),  # North behind       -> facing South
        (1.0, 0.0, 270.0),   # North to the right -> facing West
    ])
    def test_cardinal_headings(self, mx, my, expected):
        assert basic_heading(mx, my) == pytest.approx(expected, abs=1e-6)

    def test_turning_right_increases_heading(self):
        # Rotate the measured North vector clockwise (device turns right);
        # heading should increase through 0->90->180->270.
        seq = [basic_heading(mx, my) for (mx, my) in
               [(0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1)]]
        assert seq == pytest.approx([0.0, 45.0, 90.0, 135.0, 180.0], abs=1e-6)

    def test_range_is_0_to_360(self):
        for deg in range(0, 360, 7):
            import math
            mx, my = math.cos(math.radians(deg)), math.sin(math.radians(deg))
            h = basic_heading(mx, my)
            assert 0.0 <= h < 360.0


class TestTiltCompensatedHeading:
    def test_level_reduces_to_basic(self):
        # With gravity straight down/up along Z, tilt comp == basic heading.
        for mx, my in [(0, 1), (1, 0), (0.5, -0.5), (-0.3, 0.8)]:
            level = tilt_compensated_heading(mx, my, 0.7, 0.0, 0.0, 1.0)
            assert level == pytest.approx(basic_heading(mx, my), abs=1e-6)

    def test_gravity_sign_does_not_matter(self):
        up = tilt_compensated_heading(0.3, 0.9, 0.2, 0.0, 0.0, 1.0)
        down = tilt_compensated_heading(0.3, 0.9, 0.2, 0.0, 0.0, -1.0)
        assert up == pytest.approx(down, abs=1e-6)

    def test_pitch_tilt_recovers_heading_and_naive_fails(self):
        # Device facing EAST (heading 90), field has a strong vertical (inclination)
        # component, then pitched nose-down 25°. Naive heading is corrupted by the
        # vertical field leaking into +Y; tilt compensation removes it and recovers
        # 90° exactly (pure pitch + unit gravity => exact for this method).
        import math
        p = math.radians(25.0)
        b_h, b_v = 0.44, 0.90          # horizontal / vertical field components
        # facing East, level: North points to device -X -> mag_level = (-b_h, 0, b_v)
        mag = (-b_h, b_v * math.sin(p), b_v * math.cos(p))
        grav = (0.0, math.sin(p), math.cos(p))   # unit gravity, nose-down pitch

        tilt = tilt_compensated_heading(*mag, *grav)
        naive = basic_heading(mag[0], mag[1])

        assert tilt == pytest.approx(90.0, abs=1e-6)
        assert abs(naive - 90.0) > 5.0   # naive is meaningfully wrong under tilt


class TestDeclination:
    def test_sydney_declination_applied(self):
        assert apply_declination(0.0, SYDNEY_DECLINATION_DEG) == pytest.approx(12.7)

    def test_wraps_below_zero(self):
        assert apply_declination(355.0, 12.7) == pytest.approx((367.7) % 360.0)

    def test_negative_declination_wraps(self):
        assert apply_declination(5.0, -12.7) == pytest.approx(352.3)


class TestCardinal:
    @pytest.mark.parametrize("deg, label", [
        (0, 'N'), (90, 'E'), (180, 'S'), (270, 'W'),
        (45, 'NE'), (359, 'N'), (22, 'NNE'), (350, 'N'),
    ])
    def test_labels(self, deg, label):
        assert degrees_to_cardinal(deg) == label
