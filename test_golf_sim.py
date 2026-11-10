import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np

from golf_sim import (
    Ball,
    BOUNCE_FRICTION,
    CLUBS,
    Course,
    DEFORMATION_ASYMMETRY_SCALE,
    Environment,
    DONE,
    FLIGHT,
    BUNKER,
    FAIRWAY,
    GREEN,
    IN_WATER,
    OUT_OF_BOUNDS,
    ROUGH,
    SKID_FRICTION,
    STATIC_FRICTION,
    NORMAL_RESTITUTION,
    TANGENTIAL_RESTITUTION,
    TEE,
    Result,
    ShotModifiers,
    bounce,
    contact_point_slip,
    crater_angle,
    draw_standard_normals,
    flight_accel,
    impact_angle_from_normal_deg,
    landing_density,
    launch_conditions,
    lie_launch_modifier,
    make_test_hole,
    required_static_friction,
    skid_step,
    simulate,
    _last_safe_crossing,
)
from course_spec import CourseSpec, test_hole_spec


class CourseSpecTests(unittest.TestCase):
    def test_spec_round_trip(self):
        spec = test_hole_spec()
        with TemporaryDirectory() as directory:
            path = Path(directory) / "course.json"
            spec.to_json(path)
            loaded = CourseSpec.from_json(path)
        self.assertEqual(loaded, spec)

    def test_compiled_green_blends_without_cliff(self):
        course = make_test_hole(dx=0.5)
        # The old hard-mask overwrite produced meter-scale vertical walls at
        # the ellipse. A feathered feature should remain locally continuous.
        local = course.H[720:841, 70:171]
        max_step = max(
            float(np.max(np.abs(np.diff(local, axis=0)))),
            float(np.max(np.abs(np.diff(local, axis=1)))),
        )
        self.assertLess(max_step, 0.25)

    def test_mid_hole_bunker_has_large_sand_test_area(self):
        course = make_test_hole(dx=0.5)
        _, _, _, surfaces, inside = course.sample(
            np.array([262.0, 275.0]), np.array([-20.0, -20.0])
        )

        self.assertTrue(np.all(inside))
        np.testing.assert_array_equal(surfaces, np.array([BUNKER, BUNKER]))

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


class LieLaunchModifierTests(unittest.TestCase):
    def test_driver_distinguishes_tee_from_fairway(self):
        tee = lie_launch_modifier(CLUBS["driver"], "stock", TEE)
        fairway = lie_launch_modifier(CLUBS["driver"], "stock", FAIRWAY)

        self.assertEqual(tee.speed_multiplier, 1.0)
        self.assertEqual(tee.dispersion_multiplier, 1.0)
        self.assertEqual(fairway.speed_multiplier, 0.82)
        self.assertEqual(fairway.dispersion_multiplier, 1.55)
        self.assertEqual(fairway.launch_angle_offset_deg, -2.0)
        self.assertEqual(fairway.spin_multiplier, 0.80)

    def test_rough_full_recovers_speed_but_widens_dispersion(self):
        modifier = lie_launch_modifier(CLUBS["5iron"], "full", ROUGH)

        self.assertAlmostEqual(modifier.speed_multiplier, 0.92)
        self.assertAlmostEqual(modifier.dispersion_multiplier, 1.40 * 1.25)

    def test_bad_lies_increase_shape_uncertainty(self):
        rough = lie_launch_modifier(CLUBS["7iron"], "draw", ROUGH)
        bunker = lie_launch_modifier(CLUBS["pw"], "fade", BUNKER)

        self.assertEqual(rough.shot_type_mean_offset_multiplier, 0.55)
        self.assertEqual(rough.spin_axis_dispersion_multiplier, 1.25)
        self.assertEqual(bunker.shot_type_mean_offset_multiplier, 0.20)
        self.assertEqual(bunker.spin_axis_dispersion_multiplier, 1.60)

    def test_lie_and_item_modifiers_compose_in_launch_conditions(self):
        samples = np.zeros((1, 5))
        club = CLUBS["driver"]
        lie = lie_launch_modifier(club, "stock", FAIRWAY)
        _, _, params = launch_conditions(
            samples,
            club,
            "stock",
            0.0,
            item_modifiers=ShotModifiers(speed_multiplier=1.1),
            lie_modifier=lie,
        )

        self.assertAlmostEqual(params["speed"][0], club.ball_speed * 0.82 * 1.1)
        self.assertAlmostEqual(params["launch"][0], club.launch_deg - 2.0)
        self.assertAlmostEqual(params["spin"][0], club.spin_rpm * 0.80)


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

    def test_out_of_bounds_density_remains_outside_playable_course(self):
        finish_position = np.array([[230.0, -75.0]])
        result = Result(
            rest=finish_position,
            status=np.array([OUT_OF_BOUNDS]),
            surface=np.array([0]),
            first_land=finish_position.copy(),
            paths=[],
        )
        course = make_test_hole()

        _, centers_y, density, _ = landing_density(course, result)
        peak_y = centers_y[np.unravel_index(np.argmax(density), density.shape)[1]]
        playable_y_min = course.y0

        self.assertLess(peak_y, playable_y_min)
        self.assertAlmostEqual(float(density.sum()), 1.0, places=10)


class OutOfBoundsTrajectoryTests(unittest.TestCase):
    def test_airborne_shot_continues_past_playable_boundary(self):
        course = make_test_hole()
        result = simulate(
            course,
            v0=np.array([[0.0, 30.0, 15.0]]),
            w0=np.zeros((1, 3)),
            start_xy=np.array([100.0, 0.0]),
            env=Environment(air_density=0.0),
            dt=0.02,
            keep_paths=1,
        )

        playable_y_max = course.y0 + (course.ny - 1) * course.dx
        self.assertEqual(result.status[0], OUT_OF_BOUNDS)
        self.assertGreater(result.rest[0, 1], playable_y_max + 10.0)
        self.assertGreater(result.paths[0][-1, 1], playable_y_max + 10.0)


class ReliefBoundaryTests(unittest.TestCase):
    def test_crossing_point_stays_on_dry_side_of_water_boundary(self):
        heights = np.zeros((21, 3))
        surfaces = np.zeros((21, 3), dtype=int)
        surfaces[10:, :] = 4
        course = Course(0.0, -1.0, 1.0, heights, surfaces)

        crossing = _last_safe_crossing(
            course,
            np.array([8.0, 0.0]),
            np.array([12.0, 0.0]),
            lambda xy: int(course.sample(xy[0], xy[1])[3]) != 4,
        )

        self.assertEqual(int(course.sample(crossing[0], crossing[1])[3]), 0)
        self.assertGreater(crossing[0], 9.0)
        self.assertLess(crossing[0], 10.0)


class CourseResolutionTests(unittest.TestCase):
    def test_grid_spacing_changes_resolution_without_changing_extent(self):
        fine = make_test_hole(dx=0.5)
        coarse = make_test_hole(dx=4.0)

        self.assertGreater(fine.nx * fine.ny, coarse.nx * coarse.ny)
        self.assertAlmostEqual(fine.x0 + (fine.nx - 1) * fine.dx, 420.0)
        self.assertAlmostEqual(coarse.x0 + (coarse.nx - 1) * coarse.dx, 420.0)
        self.assertAlmostEqual(fine.y0 + (fine.ny - 1) * fine.dx, 60.0)
        self.assertAlmostEqual(coarse.y0 + (coarse.ny - 1) * coarse.dx, 60.0)


class BounceModelTests(unittest.TestCase):
    def test_recorded_path_phases_align_with_recorded_positions(self):
        course = make_test_hole(dx=1.0)
        result = simulate(
            course,
            np.array([[35.0, 0.0, 18.0]]),
            np.zeros((1, 3)),
            np.array([5.0, 0.0]),
            dt=0.05,
            keep_paths=1,
        )

        self.assertEqual(len(result.paths[0]), len(result.path_phases[0]))
        self.assertEqual(int(result.path_phases[0][0]), FLIGHT)
        self.assertEqual(int(result.path_phases[0][-1]), DONE)

    def test_impact_angle_is_measured_from_surface_normal(self):
        angles = impact_angle_from_normal_deg(
            np.array([-10.0, -10.0, -1.0]),
            np.array([0.0, 10.0, 100.0]),
        )
        np.testing.assert_allclose(angles[:2], [0.0, 45.0])
        self.assertGreater(angles[2], 89.0)

    def test_green_deformation_uses_active_surface_multiplier(self):
        angle = crater_angle(
            np.array([18.6]),
            np.array([44.4]),
            np.array([2]),
        )
        expected = np.degrees(
            np.arctan(
                np.tan(np.radians(15.4))
                * DEFORMATION_ASYMMETRY_SCALE
                * 0.35
            )
        )
        self.assertAlmostEqual(float(np.degrees(angle[0])), float(expected))

    def test_rough_uses_less_deformation_rotation_than_fairway(self):
        angles = crater_angle(
            np.array([18.6, 18.6]),
            np.array([44.4, 44.4]),
            np.array([ROUGH, FAIRWAY]),
        )
        self.assertLess(float(angles[0]), float(angles[1]))

    def test_vertical_impact_has_zero_crater_angle(self):
        angle = crater_angle(
            np.array([50.0]),
            np.array([0.0]),
            np.array([0]),
        )
        self.assertAlmostEqual(float(angle[0]), 0.0)

    def test_crater_angle_is_speed_independent(self):
        angles = crater_angle(
            np.array([1.0, 500.0]),
            np.array([45.0, 45.0]),
            np.array([2, 2]),
        )
        self.assertAlmostEqual(float(angles[0]), float(angles[1]))

    def test_grazing_impact_has_zero_crater_angle(self):
        angle = crater_angle(
            np.array([50.0]),
            np.array([90.0]),
            np.array([0]),
        )
        self.assertAlmostEqual(float(angle[0]), 0.0, places=12)

    def test_crater_angle_peaks_near_45_degrees(self):
        angles = crater_angle(
            np.full(3, 30.0),
            np.array([20.0, 45.0, 70.0]),
            np.full(3, 2),
        )
        self.assertGreater(float(angles[1]), float(angles[0]))
        self.assertGreater(float(angles[1]), float(angles[2]))

    def test_crater_angle_vanishes_faster_than_grazing_incidence(self):
        incidence_from_plane_deg = np.array([5.0, 1.0, 0.2])
        angle = crater_angle(
            np.full(3, 50.0),
            90.0 - incidence_from_plane_deg,
            np.full(3, ROUGH),
        )
        ratio_to_incidence = np.degrees(angle) / incidence_from_plane_deg

        self.assertGreater(ratio_to_incidence[0], ratio_to_incidence[1])
        self.assertGreater(ratio_to_incidence[1], ratio_to_incidence[2])

    def test_crater_angle_vanishes_faster_than_near_vertical_incidence(self):
        incidence_from_normal_deg = np.array([5.0, 1.0, 0.2])
        angle = crater_angle(
            np.full(3, 50.0),
            incidence_from_normal_deg,
            np.full(3, ROUGH),
        )
        ratio_to_incidence = np.degrees(angle) / incidence_from_normal_deg

        self.assertGreater(ratio_to_incidence[0], ratio_to_incidence[1])
        self.assertGreater(ratio_to_incidence[1], ratio_to_incidence[2])

    def test_vertical_spin_free_impacts_rebound_without_horizontal_kick(self):
        speeds = np.array([30.0, 60.0, 100.0])
        velocity = np.column_stack(
            [np.zeros_like(speeds), np.zeros_like(speeds), -speeds]
        )

        for surface in (FAIRWAY, ROUGH):
            new_velocity, _, new_normal_velocity = bounce(
                velocity,
                np.zeros_like(velocity),
                np.zeros_like(speeds),
                np.zeros_like(speeds),
                np.full(len(speeds), surface),
                Ball(),
            )
            np.testing.assert_allclose(new_velocity[:, 0], 0.0, atol=1e-12)
            self.assertTrue(np.all(new_normal_velocity > 0.0))

    def test_directional_restitution_matches_effective_plane_components(self):
        velocity = np.array([[20.0, 0.0, -20.0]])
        surface = FAIRWAY
        theta = crater_angle(
            np.array([np.linalg.norm(velocity[0])]),
            np.array([45.0]),
            np.array([surface]),
        )[0]
        normal = np.array([[-np.sin(theta), 0.0, np.cos(theta)]])
        incoming_normal = np.sum(velocity * normal, axis=1, keepdims=True)
        incoming_tangent = velocity - incoming_normal * normal
        expected_velocity = (
            TANGENTIAL_RESTITUTION[surface] * incoming_tangent
            - NORMAL_RESTITUTION[surface] * incoming_normal * normal
        )

        original_friction = BOUNCE_FRICTION[surface]
        try:
            BOUNCE_FRICTION[surface] = 0.0
            new_velocity, _, _ = bounce(
                velocity,
                np.zeros_like(velocity),
                np.zeros(1),
                np.zeros(1),
                np.array([surface]),
                Ball(),
            )
        finally:
            BOUNCE_FRICTION[surface] = original_friction

        np.testing.assert_allclose(
            new_velocity,
            expected_velocity,
            rtol=1e-9,
            atol=1e-12,
        )

    def test_surface_rebound_liveliness_has_intended_order(self):
        velocity = np.repeat([[0.0, 0.0, -10.0]], 5, axis=0)
        surfaces = np.array([GREEN, FAIRWAY, TEE, ROUGH, BUNKER])
        new_velocity, _, _ = bounce(
            velocity,
            np.zeros_like(velocity),
            np.zeros(5),
            np.zeros(5),
            surfaces,
            Ball(),
        )
        rebound = new_velocity[:, 2]

        self.assertGreater(rebound[1], rebound[0])
        self.assertAlmostEqual(float(rebound[1]), float(rebound[2]))
        self.assertGreater(rebound[3], rebound[0])
        self.assertGreater(rebound[0], rebound[4])

    def test_flat_bunker_impact_has_no_normal_rebound(self):
        new_velocity, _, new_normal_velocity = bounce(
            np.array([[20.0, 0.0, -20.0]]),
            np.array([[0.0, -500.0, 0.0]]),
            np.array([0.0]),
            np.array([0.0]),
            np.array([BUNKER]),
            Ball(),
        )

        self.assertAlmostEqual(float(new_normal_velocity[0]), 0.0, places=12)
        self.assertAlmostEqual(float(new_velocity[0, 2]), 0.0, places=12)

    def test_skid_friction_reduces_contact_slip_and_total_energy(self):
        ball = Ball()
        normal = np.array([[0.0, 0.0, 1.0]])
        velocity = np.array([[12.0, 0.0, 0.0]])
        omega = np.zeros((1, 3))
        slip0 = np.linalg.norm(contact_point_slip(velocity, omega, normal, ball))
        energy0 = 0.5 * np.sum(velocity ** 2) + (
            0.5 * ball.inertia_k * ball.radius ** 2 * np.sum(omega ** 2)
        )

        new_velocity, new_omega, slip1 = skid_step(
            velocity,
            omega,
            normal,
            np.array([FAIRWAY]),
            ball,
            Environment(),
            0.1,
        )
        energy1 = 0.5 * np.sum(new_velocity ** 2) + (
            0.5 * ball.inertia_k * ball.radius ** 2 * np.sum(new_omega ** 2)
        )

        self.assertLess(float(slip1[0]), float(slip0))
        self.assertLess(float(energy1), float(energy0))

    def test_backspin_checks_forward_velocity_during_skid(self):
        ball = Ball()
        normal = np.array([[0.0, 0.0, 1.0]])
        velocity = np.array([[8.0, 0.0, 0.0]])
        # Negative y spin makes the bottom of the ball slip forward here;
        # friction therefore checks its forward center-of-mass motion.
        omega = np.array([[0.0, -600.0, 0.0]])

        new_velocity, new_omega, slip = skid_step(
            velocity,
            omega,
            normal,
            np.array([FAIRWAY]),
            ball,
            Environment(),
            0.1,
        )

        self.assertLess(float(new_velocity[0, 0]), float(velocity[0, 0]))
        self.assertLess(abs(float(new_omega[0, 1])), abs(float(omega[0, 1])))
        self.assertLess(
            float(slip[0]),
            float(np.linalg.norm(contact_point_slip(velocity, omega, normal, ball))),
        )

    def test_skid_step_stops_at_pure_rolling_without_overshoot(self):
        ball = Ball()
        normal = np.array([[0.0, 0.0, 1.0]])
        velocity = np.array([[1.0, 0.0, 0.0]])
        omega = np.zeros((1, 3))

        new_velocity, new_omega, slip = skid_step(
            velocity,
            omega,
            normal,
            np.array([FAIRWAY]),
            ball,
            Environment(),
            10.0,
        )

        self.assertLess(float(slip[0]), 1e-10)
        self.assertAlmostEqual(float(new_velocity[0, 0]), 5.0 / 7.0)
        self.assertAlmostEqual(
            float(new_omega[0, 1]), new_velocity[0, 0] / ball.radius
        )

    def test_contact_friction_tables_are_independent(self):
        self.assertFalse(np.shares_memory(BOUNCE_FRICTION, SKID_FRICTION))
        self.assertFalse(np.shares_memory(SKID_FRICTION, STATIC_FRICTION))
        self.assertGreater(SKID_FRICTION[BUNKER], BOUNCE_FRICTION[BUNKER])
        self.assertGreater(SKID_FRICTION[BUNKER], STATIC_FRICTION[BUNKER])

    def test_static_friction_requirement_matches_solid_sphere_slope(self):
        ball = Ball()
        flat = np.array([[0.0, 0.0, 1.0]])
        slope_45 = np.array([[1.0, 0.0, 1.0]]) / np.sqrt(2.0)

        self.assertAlmostEqual(float(required_static_friction(flat, ball)[0]), 0.0)
        self.assertAlmostEqual(
            float(required_static_friction(slope_45, ball)[0]),
            ball.inertia_k / (1.0 + ball.inertia_k),
        )


if __name__ == "__main__":
    unittest.main()
