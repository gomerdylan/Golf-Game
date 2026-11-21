import unittest

import numpy as np

import physics_worker


class PhysicsWorkerTests(unittest.TestCase):
    def setUp(self):
        self.settings = {
            "aim_deg": 3.25,
            "club": "driver",
            "shot_type": "stock",
            "modifiers": {},
            "environment": {},
        }

    def test_preview_is_repeatable_for_same_context(self):
        request = {
            "settings": self.settings,
            "preview_seed": 1234,
            "sample_count": 40,
        }
        first = physics_worker.preview(request)
        second = physics_worker.preview(request)
        self.assertEqual(first, second)
        self.assertEqual(
            len(first["preview_paths_xyz_m"]), physics_worker.PREVIEW_PATH_COUNT
        )

    def test_fog_bandwidth_adapts_to_endpoint_spread(self):
        compact = np.array([
            [1.00, 0.00], [1.05, 0.02], [0.98, -0.01], [1.02, 0.01]
        ])
        broad = compact * 100.0

        compact_bin, compact_sigma_cells, compact_bounds = (
            physics_worker._adaptive_fog_parameters(compact)
        )
        broad_bin, broad_sigma_cells, broad_bounds = (
            physics_worker._adaptive_fog_parameters(broad)
        )

        self.assertEqual(compact_bin, 0.25)
        self.assertLess(compact_bin * compact_sigma_cells,
                        broad_bin * broad_sigma_cells)
        self.assertLess(compact_bounds[1] - compact_bounds[0],
                        broad_bounds[1] - broad_bounds[0])

    def test_actual_shot_uses_separate_seed(self):
        first = physics_worker.shoot(
            {"settings": self.settings, "shot_seed": 8001}
        )
        second = physics_worker.shoot(
            {"settings": self.settings, "shot_seed": 8002}
        )
        self.assertNotEqual(first["positions_xyz_m"], second["positions_xyz_m"])

    def test_preview_excludes_mishits(self):
        base_request = {"preview_seed": 2468, "sample_count": 40}
        clean = physics_worker.preview({
            **base_request,
            "settings": {**self.settings, "mishit_chance": 0.0},
        })
        certain_mishit = physics_worker.preview({
            **base_request,
            "settings": {**self.settings, "mishit_chance": 1.0},
        })

        self.assertEqual(clean["grid"], certain_mishit["grid"])
        self.assertEqual(
            clean["preview_paths_xyz_m"],
            certain_mishit["preview_paths_xyz_m"],
        )
        self.assertEqual(clean["statistics"], certain_mishit["statistics"])

    def test_actual_shot_reports_separate_mishit_draw(self):
        clean = physics_worker.shoot({
            "settings": {**self.settings, "mishit_chance": 0.0},
            "shot_seed": 1357,
        })
        mishit = physics_worker.shoot({
            "settings": {**self.settings, "mishit_chance": 1.0},
            "shot_seed": 1357,
        })

        self.assertFalse(clean["mishit"])
        self.assertTrue(mishit["mishit"])
        self.assertTrue(mishit["mishit_key"])
        self.assertTrue(mishit["mishit_name"])
        self.assertNotEqual(clean["positions_xyz_m"], mishit["positions_xyz_m"])

    def test_debug_can_force_a_club_specific_mishit(self):
        forced = physics_worker.shoot({
            "settings": {
                **self.settings,
                "mishit_chance": 0.0,
                "forced_mishit": "top",
            },
            "shot_seed": 8642,
        })

        self.assertTrue(forced["mishit"])
        self.assertEqual(forced["mishit_key"], "top")
        self.assertEqual(forced["mishit_name"], "Topped")

        with self.assertRaisesRegex(ValueError, "unknown mis-hit"):
            physics_worker.shoot({
                "settings": {
                    **self.settings,
                    "forced_mishit": "blade",
                },
                "shot_seed": 8642,
            })

    def test_selected_club_changes_preview(self):
        driver_request = {
            "settings": self.settings,
            "preview_seed": 4321,
            "sample_count": 20,
        }
        wedge_settings = {**self.settings, "club": "pw"}
        wedge_request = {
            "settings": wedge_settings,
            "preview_seed": 4321,
            "sample_count": 20,
        }
        driver = physics_worker.preview(driver_request)
        wedge = physics_worker.preview(wedge_request)
        self.assertNotEqual(driver["grid"]["x_m"], wedge["grid"]["x_m"])

    def test_course_id_selects_the_requested_physics_terrain(self):
        settings = {**self.settings, "course_id": "water_carry"}
        result = physics_worker.preview(
            {"settings": settings, "preview_seed": 17, "sample_count": 20}
        )
        self.assertEqual(result["lie"], "tee")
        self.assertTrue(result["grid"]["x_m"])

    def test_unknown_course_id_is_rejected(self):
        settings = {**self.settings, "course_id": "missing"}
        with self.assertRaisesRegex(ValueError, "unknown course_id"):
            physics_worker.preview(
                {"settings": settings, "preview_seed": 17, "sample_count": 20}
            )

    def test_shot_starts_from_requested_ball_position(self):
        settings = {**self.settings, "start_xy_m": [230.0, -8.0]}
        result = physics_worker.shoot({"settings": settings, "shot_seed": 91})
        self.assertAlmostEqual(result["positions_xyz_m"][0][0], 230.0)
        self.assertAlmostEqual(result["positions_xyz_m"][0][1], -8.0)
        self.assertEqual(len(result["rest_xy_m"]), 2)
        self.assertEqual(len(result["relief_xy_m"]), 2)

    def test_driver_is_penalized_off_fairway_relative_to_tee(self):
        tee = physics_worker.shoot({"settings": self.settings, "shot_seed": 91})
        fairway_settings = {**self.settings, "start_xy_m": [230.0, 0.0]}
        fairway = physics_worker.shoot(
            {"settings": fairway_settings, "shot_seed": 91}
        )

        self.assertLess(fairway["launch"]["speed"], tee["launch"]["speed"])
        self.assertLess(fairway["launch"]["launch"], tee["launch"]["launch"])


if __name__ == "__main__":
    unittest.main()
