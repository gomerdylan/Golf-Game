import unittest

import numpy as np

from golf_sim import (
    CLUBS,
    IN_WATER,
    OUT_OF_BOUNDS,
    Result,
    ShotModifiers,
    draw_standard_normals,
    landing_density,
    launch_conditions,
    make_test_hole,
)


class ShotModifierTests(unittest.TestCase):
    def setUp(self):
        self.samples = draw_standard_normals(2000, np.random.default_rng(42))
        self.club = CLUBS["driver"]

    def test_speed_multiplier_scales_every_sample(self):
        baseline, _, _ = launch_conditions(self.samples, self.club, "stock", 0.0)
        faster, _, _ = launch_conditions(
            self.samples,
            self.club,
            "stock",
            0.0,
            ShotModifiers(speed_multiplier=1.2),
        )
        np.testing.assert_allclose(
            np.linalg.norm(faster, axis=1),
            1.2 * np.linalg.norm(baseline, axis=1),
        )

    def test_zero_dispersion_produces_identical_launches(self):
        velocity, spin, _ = launch_conditions(
            self.samples,
            self.club,
            "stock",
            0.0,
            ShotModifiers(dispersion_multiplier=0.0),
        )
        np.testing.assert_allclose(velocity, np.repeat(velocity[:1], len(velocity), axis=0))
        np.testing.assert_allclose(spin, np.repeat(spin[:1], len(spin), axis=0))

    def test_invalid_modifiers_are_rejected(self):
        with self.assertRaises(ValueError):
            ShotModifiers(speed_multiplier=0.0)
        with self.assertRaises(ValueError):
            ShotModifiers(dispersion_multiplier=-0.1)


class LandingDensityTests(unittest.TestCase):
    def test_water_and_out_of_bounds_landings_are_included(self):
        finish_positions = np.array([[230.0, 30.0], [230.0, -75.0]])
        result = Result(
            rest=finish_positions,
            status=np.array([IN_WATER, OUT_OF_BOUNDS]),
            surface=np.array([4, 0]),
            first_land=finish_positions.copy(),
            paths=[],
        )

        _, _, density, _ = landing_density(make_test_hole(), result)

        self.assertAlmostEqual(float(density.sum()), 2.0, places=10)


class CourseResolutionTests(unittest.TestCase):
    def test_grid_spacing_changes_resolution_without_changing_extent(self):
        fine = make_test_hole(dx=0.5)
        coarse = make_test_hole(dx=4.0)

        self.assertGreater(fine.nx * fine.ny, coarse.nx * coarse.ny)
        self.assertAlmostEqual(fine.x0 + (fine.nx - 1) * fine.dx, 420.0)
        self.assertAlmostEqual(coarse.x0 + (coarse.nx - 1) * coarse.dx, 420.0)
        self.assertAlmostEqual(fine.y0 + (fine.ny - 1) * fine.dx, 60.0)
        self.assertAlmostEqual(coarse.y0 + (coarse.ny - 1) * coarse.dx, 60.0)


if __name__ == "__main__":
    unittest.main()
