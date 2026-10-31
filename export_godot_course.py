"""Export the canonical Python test hole for the Godot frontend.

All stored coordinates and heights are meters.  Godot also treats one world
unit as one meter; yards are a presentation-layer conversion only.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from golf_sim import (
    CLUBS,
    SURFACE_COLORS,
    SURFACES,
    draw_standard_normals,
    landing_density,
    launch_conditions,
    make_test_hole,
    simulate,
)


OUTPUT_DIR = Path(__file__).parent / "godot" / "course_data" / "test_hole"


def _rgb(hex_color: str) -> list[float]:
    value = hex_color.lstrip("#")
    return [int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]


def _aim_preview(course, start_xy, aim_deg, standard_normals):
    """Calculate one cached, physics-authentic Godot preview."""
    v0, w0, _ = launch_conditions(
        np.zeros((1, 5)), CLUBS["driver"], "stock", aim_deg=aim_deg
    )
    sample_dt_s = 0.02
    representative = simulate(
        course, v0, w0, start_xy=start_xy, dt=sample_dt_s, keep_paths=1
    )
    ensemble_v0, ensemble_w0, _ = launch_conditions(
        standard_normals, CLUBS["driver"], "stock", aim_deg=aim_deg
    )
    ensemble = simulate(
        course, ensemble_v0, ensemble_w0, start_xy=start_xy, dt=0.05, keep_paths=0
    )
    centers_x, centers_y, density, _ = landing_density(
        course, ensemble, bin_size=2.0, sigma_cells=1.5, min_fraction=0.06
    )
    peak = float(density.max())
    support_indices = np.argwhere(density >= peak * 0.005)
    i0, j0 = support_indices.min(axis=0)
    i1, j1 = support_indices.max(axis=0)
    padding = 3
    i0, j0 = max(0, i0 - padding), max(0, j0 - padding)
    i1 = min(density.shape[0] - 1, i1 + padding)
    j1 = min(density.shape[1] - 1, j1 + padding)
    fog_x = centers_x[i0 : i1 + 1]
    fog_y = centers_y[j0 : j1 + 1]
    fog_density = density[i0 : i1 + 1, j0 : j1 + 1] / peak
    fog_x_grid, fog_y_grid = np.meshgrid(fog_x, fog_y, indexing="ij")
    fog_height = course.sample(fog_x_grid, fog_y_grid)[0]
    return {
        "sample_dt_s": sample_dt_s,
        "positions_xyz_m": representative.paths[0].round(6).tolist(),
        "grid": {
            "x_m": fog_x.round(6).tolist(),
            "y_m": fog_y.round(6).tolist(),
            "height_m": fog_height.round(6).tolist(),
            "density": fog_density.round(7).tolist(),
        },
    }


def export_test_hole(output_dir: Path = OUTPUT_DIR, spacing_m: float = 0.5) -> Path:
    course = make_test_hole(dx=spacing_m)
    output_dir.mkdir(parents=True, exist_ok=True)

    # C-order matches the Course convention: height[x_index, y_index].
    np.asarray(course.H, dtype="<f4").tofile(output_dir / "height_f32.bin")
    np.asarray(course.S, dtype=np.uint8).tofile(output_dir / "surface_u8.bin")

    metadata = {
        "format_version": 1,
        "units": "meters",
        "godot_mapping": {
            "physics_x_downrange": "godot_-z",
            "physics_y_left": "godot_-x",
            "physics_z_up": "godot_+y",
        },
        "x0_m": float(course.x0),
        "y0_m": float(course.y0),
        "spacing_m": float(course.dx),
        "nx": int(course.nx),
        "ny": int(course.ny),
        "surfaces": [
            {"id": index, "name": name, "rgb": _rgb(color)}
            for index, (name, color) in enumerate(zip(SURFACES, SURFACE_COLORS))
        ],
        "tee_m": [0.0, 0.0],
        "cup_m": [385.0, -5.0],
    }
    (output_dir / "course.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )

    # One nominal stock-driver shot gives the frontend a deterministic first
    # animation. Zeros select the mean launch conditions, without random miss.
    start_xy = np.array([5.0, 0.0])
    v0, w0, launch = launch_conditions(
        np.zeros((1, 5)), CLUBS["driver"], "stock", aim_deg=0.0
    )
    sample_dt_s = 0.02
    result = simulate(
        course,
        v0,
        w0,
        start_xy=start_xy,
        dt=sample_dt_s,
        keep_paths=1,
    )
    trajectory = {
        "format_version": 1,
        "units": "meters",
        "sample_dt_s": sample_dt_s,
        "club": "driver",
        "shot_type": "stock",
        "launch": {key: float(values[0]) for key, values in launch.items()},
        "positions_xyz_m": result.paths[0].round(6).tolist(),
    }
    (output_dir / "trajectory.json").write_text(
        json.dumps(trajectory, separators=(",", ":")) + "\n", encoding="utf-8"
    )

    # Export a physics-derived landing distribution for the Godot shot preview.
    # The frontend only renders these cells; it does not invent or reshape the
    # probabilities calculated here.
    rng = np.random.default_rng(2)
    sample_count = 500
    ensemble_v0, ensemble_w0, _ = launch_conditions(
        draw_standard_normals(sample_count, rng),
        CLUBS["driver"],
        "stock",
        aim_deg=0.0,
    )
    ensemble = simulate(
        course,
        ensemble_v0,
        ensemble_w0,
        start_xy=start_xy,
        dt=0.05,
        keep_paths=0,
    )
    centers_x, centers_y, density, visible = landing_density(
        course, ensemble, bin_size=2.0, sigma_cells=1.5, min_fraction=0.06
    )
    peak = float(density.max())
    fog_cells = []
    for i, j in np.argwhere(visible):
        x = float(centers_x[i])
        y = float(centers_y[j])
        height = float(course.sample(x, y)[0])
        fog_cells.append([x, y, height, float(density[i, j] / peak)])

    # A cropped regular grid lets the GPU interpolate between physics bins. A
    # small low-density border gives the shader room to fade out smoothly.
    support = density >= peak * 0.005
    support_indices = np.argwhere(support)
    i0, j0 = support_indices.min(axis=0)
    i1, j1 = support_indices.max(axis=0)
    padding = 3
    i0, j0 = max(0, i0 - padding), max(0, j0 - padding)
    i1 = min(density.shape[0] - 1, i1 + padding)
    j1 = min(density.shape[1] - 1, j1 + padding)
    fog_x = centers_x[i0 : i1 + 1]
    fog_y = centers_y[j0 : j1 + 1]
    fog_density = density[i0 : i1 + 1, j0 : j1 + 1] / peak
    fog_x_grid, fog_y_grid = np.meshgrid(fog_x, fog_y, indexing="ij")
    fog_height = course.sample(fog_x_grid, fog_y_grid)[0]
    probability_fog = {
        "format_version": 1,
        "units": "meters",
        "samples": sample_count,
        "seed": 2,
        "cells_xyz_density": fog_cells,
        "grid": {
            "x_m": fog_x.round(6).tolist(),
            "y_m": fog_y.round(6).tolist(),
            "height_m": fog_height.round(6).tolist(),
            "density": fog_density.round(7).tolist(),
        },
    }
    (output_dir / "probability_fog.json").write_text(
        json.dumps(probability_fog, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    # A small cache makes aiming instantaneous in Godot while every displayed
    # preview still comes from a full Python simulation against this terrain.
    # Five-degree increments are deliberately coarse for this first UI pass.
    common_normals = draw_standard_normals(500, np.random.default_rng(2))
    aim_angles = list(range(-30, 31, 5))
    aim_previews = {
        str(angle): _aim_preview(course, start_xy, angle, common_normals)
        for angle in aim_angles
    }
    (output_dir / "aim_previews.json").write_text(
        json.dumps(
            {
                "format_version": 1,
                "units": "meters",
                "samples_per_preview": 500,
                "angle_step_deg": 5,
                "previews": aim_previews,
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    return output_dir


if __name__ == "__main__":
    destination = export_test_hole()
    print(f"Exported test hole (meters) to {destination}")
