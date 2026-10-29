import unittest

import numpy as np

from golf_sim import (
    CLUBS,
    ShotModifiers,
    draw_standard_normals,
    launch_conditions,
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


if __name__ == "__main__":
    unittest.main()
