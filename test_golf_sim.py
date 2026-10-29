import unittest

import numpy as np

from golf_sim import (
    Ball,
    CLUBS,
    Environment,
    IN_WATER,
    OUT_OF_BOUNDS,
    Result,
    ShotModifiers,
    draw_standard_normals,
    flight_accel,
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
        with self.assertRaises(ValueError):
            ShotModifiers(spin_multiplier=-0.1)
        with self.assertRaises(ValueError):
            ShotModifiers(start_direction_dispersion_multiplier=-0.1)
        with self.assertRaises(ValueError):
            ShotModifiers(spin_axis_dispersion_multiplier=-0.1)

    def test_launch_angle_and_spin_modifiers_change_means(self):
        _, _, params = launch_conditions(
            self.samples,
            self.club,
            "stock",
            0.0,
            ShotModifiers(
                dispersion_multiplier=0.0,
                launch_angle_offset_deg=7.0,
                spin_multiplier=1.5,
            ),
        )

        np.testing.assert_allclose(params["launch"], self.club.launch_deg + 7.0)
        np.testing.assert_allclose(params["spin"], self.club.spin_rpm * 1.5)

    def test_directional_dispersion_can_be_removed_independently(self):
        _, _, params = launch_conditions(
            self.samples,
            self.club,
            "stock",
            0.0,
            ShotModifiers(
                start_direction_dispersion_multiplier=0.0,
                spin_axis_dispersion_multiplier=0.0,
            ),
        )

        np.testing.assert_allclose(params["start"], 0.0)
        np.testing.assert_allclose(params["axis"], 0.0)

    def test_spin_axis_offset_stacks_with_shot_shape(self):
        modifiers = ShotModifiers(
            dispersion_multiplier=0.0,
            spin_axis_offset_deg=20.0,
        )
        _, _, stock = launch_conditions(
            self.samples, self.club, "stock", 0.0, modifiers
        )
        _, _, draw = launch_conditions(
            self.samples, self.club, "draw", 0.0, modifiers
        )
        _, _, fade = launch_conditions(
            self.samples, self.club, "fade", 0.0, modifiers
        )

        np.testing.assert_allclose(stock["axis"], 20.0)
        np.testing.assert_allclose(draw["axis"], 14.0)
        np.testing.assert_allclose(fade["axis"], 26.0)
        np.testing.assert_allclose(draw["start"], 2.0)
        np.testing.assert_allclose(fade["start"], -2.0)
        np.testing.assert_allclose(draw["spin"], self.club.spin_rpm * 0.95)
        np.testing.assert_allclose(fade["spin"], self.club.spin_rpm * 1.05)


class AerodynamicModifierTests(unittest.TestCase):
    def test_magnus_multiplier_scales_lift(self):
        velocity = np.array([[60.0, 0.0, 10.0]])
        backspin = np.array([[0.0, -300.0, 0.0]])
        no_lift = flight_accel(
            velocity,
            backspin,
            Ball(),
            Environment(magnus_lift_multiplier=0.0),
        )
        extra_lift = flight_accel(
            velocity,
            backspin,
            Ball(),
            Environment(magnus_lift_multiplier=2.0),
        )

        self.assertGreater(extra_lift[0, 2], no_lift[0, 2])

    def test_drag_multiplier_and_tailwind_change_deceleration(self):
        velocity = np.array([[60.0, 0.0, 0.0]])
        no_spin = np.zeros((1, 3))
        no_drag = flight_accel(
            velocity,
            no_spin,
            Ball(),
            Environment(drag_multiplier=0.0),
        )
        ordinary_drag = flight_accel(
            velocity,
            no_spin,
            Ball(),
            Environment(),
        )
        tailwind_drag = flight_accel(
            velocity,
            no_spin,
            Ball(),
            Environment(wind=np.array([20.0, 0.0, 0.0])),
        )

        self.assertAlmostEqual(float(no_drag[0, 0]), 0.0)
        self.assertLess(ordinary_drag[0, 0], tailwind_drag[0, 0])
        self.assertLess(tailwind_drag[0, 0], 0.0)

    def test_gravity_multiplier_changes_vertical_acceleration(self):
        velocity = np.array([[60.0, 0.0, 0.0]])
        no_spin = np.zeros((1, 3))
        low_gravity = flight_accel(
            velocity,
            no_spin,
            Ball(),
            Environment(drag_multiplier=0.0, gravity_multiplier=0.5),
        )
        high_gravity = flight_accel(
            velocity,
            no_spin,
            Ball(),
            Environment(drag_multiplier=0.0, gravity_multiplier=2.0),
        )

        self.assertLess(high_gravity[0, 2], low_gravity[0, 2])

    def test_zero_air_density_removes_drag_and_magnus(self):
        velocity = np.array([[60.0, 0.0, 10.0]])
        backspin = np.array([[0.0, -300.0, 0.0]])
        vacuum = flight_accel(
            velocity,
            backspin,
            Ball(),
            Environment(
                air_density=0.0,
                drag_multiplier=3.0,
                magnus_lift_multiplier=5.0,
            ),
        )

        np.testing.assert_allclose(vacuum, np.array([[0.0, 0.0, -9.81]]))

    def test_invalid_environment_modifiers_are_rejected(self):
        with self.assertRaises(ValueError):
            Environment(spin_decay_tau=0.0)
        with self.assertRaises(ValueError):
            Environment(magnus_lift_multiplier=-0.1)
        with self.assertRaises(ValueError):
            Environment(air_density=-0.1)
        with self.assertRaises(ValueError):
            Environment(drag_multiplier=-0.1)
        with self.assertRaises(ValueError):
            Environment(gravity_multiplier=0.0)


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
