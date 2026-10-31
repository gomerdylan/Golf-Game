import unittest

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

    def test_actual_shot_uses_separate_seed(self):
        first = physics_worker.shoot(
            {"settings": self.settings, "shot_seed": 8001}
        )
        second = physics_worker.shoot(
            {"settings": self.settings, "shot_seed": 8002}
        )
        self.assertNotEqual(first["positions_xyz_m"], second["positions_xyz_m"])

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

    def test_shot_starts_from_requested_ball_position(self):
        settings = {**self.settings, "start_xy_m": [230.0, -8.0]}
        result = physics_worker.shoot({"settings": settings, "shot_seed": 91})
        self.assertAlmostEqual(result["positions_xyz_m"][0][0], 230.0)
        self.assertAlmostEqual(result["positions_xyz_m"][0][1], -8.0)
        self.assertEqual(len(result["rest_xy_m"]), 2)
        self.assertEqual(len(result["relief_xy_m"]), 2)


if __name__ == "__main__":
    unittest.main()
