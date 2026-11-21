"""Persistent JSON-lines physics service for the Godot prototype.

Stdout is protocol-only. Diagnostics belong on stderr so they cannot corrupt
messages. Closing the parent pipe or sending ``shutdown`` ends the process.
"""

from __future__ import annotations

import json
import sys
import numpy as np

from golf_sim import (
    CLUBS,
    Environment,
    ShotModifiers,
    SURFACES,
    draw_standard_normals,
    landing_density,
    launch_conditions,
    lie_launch_modifier,
    make_test_hole,
    make_water_carry_hole,
    shot_statistics,
    simulate,
)


PROTOCOL_VERSION = 1
COURSES = {
    "test_hole": make_test_hole(dx=0.5),
    "water_carry": make_water_carry_hole(dx=0.5),
}
DEFAULT_START_XY = np.array([5.0, 0.0])
PREVIEW_PATH_COUNT = 12
_preview_cache: dict[str, dict] = {}


def _settings(request: dict):
    settings = request.get("settings", {})
    course_id = settings.get("course_id", "test_hole")
    if course_id not in COURSES:
        raise ValueError(f"unknown course_id: {course_id}")
    course = COURSES[course_id]
    club = CLUBS[settings.get("club", "driver")]
    shot_type = settings.get("shot_type", "stock")
    shot_power = float(settings.get("shot_power", 1.0))
    aim_deg = float(settings.get("aim_deg", 0.0))
    modifiers = ShotModifiers(**settings.get("modifiers", {}))
    environment = Environment(**settings.get("environment", {}))
    start_xy = np.asarray(
        settings.get("start_xy_m", DEFAULT_START_XY), dtype=float
    )
    if start_xy.shape != (2,) or not np.all(np.isfinite(start_xy)):
        raise ValueError("start_xy_m must contain two finite coordinates")
    return (
        settings, course, club, shot_type, shot_power, aim_deg,
        modifiers, environment, start_xy,
    )


def _adaptive_fog_parameters(finish_positions: np.ndarray) -> tuple[float, float, tuple]:
    """Choose a local fog grid and KDE bandwidth from the endpoint spread.

    The previous fixed 3 m Gaussian bandwidth was appropriate for drives but
    could be larger than an entire low-power chip. Robust 10–90% spans estimate
    the physical cloud scale without letting a few wild outcomes dominate it.
    Scott's n^(-1/6) factor is the standard sample-count scaling for a 2D KDE.
    """
    points = np.asarray(finish_positions, dtype=float)
    finite = points[np.all(np.isfinite(points), axis=1)]
    if len(finite) == 0:
        raise ValueError("fog requires at least one finite finish position")

    q10, q90 = np.percentile(finite, [10.0, 90.0], axis=0)
    robust_axis_sigma = (q90 - q10) / 2.563
    robust_scale = float(np.sqrt(np.mean(robust_axis_sigma ** 2)))
    scott_factor = len(finite) ** (-1.0 / 6.0)
    bandwidth_m = float(np.clip(robust_scale * scott_factor, 0.25, 3.0))
    bin_size_m = float(np.clip(bandwidth_m / 1.5, 0.25, 2.0))
    sigma_cells = bandwidth_m / bin_size_m

    margin_m = 4.0 * bandwidth_m + 3.0 * bin_size_m
    bounds = (
        float(finite[:, 0].min() - margin_m),
        float(finite[:, 0].max() + margin_m),
        float(finite[:, 1].min() - margin_m),
        float(finite[:, 1].max() + margin_m),
    )
    return bin_size_m, sigma_cells, bounds


def _fog_grid(course, result) -> dict:
    bin_size_m, sigma_cells, bounds = _adaptive_fog_parameters(result.rest)
    centers_x, centers_y, density, _ = landing_density(
        course,
        result,
        bin_size=bin_size_m,
        sigma_cells=sigma_cells,
        min_fraction=0.06,
        bounds=bounds,
    )
    peak = float(density.max())
    support = np.argwhere(density >= peak * 0.005)
    i0, j0 = support.min(axis=0)
    i1, j1 = support.max(axis=0)
    padding = 3
    i0, j0 = max(0, i0 - padding), max(0, j0 - padding)
    i1 = min(density.shape[0] - 1, i1 + padding)
    j1 = min(density.shape[1] - 1, j1 + padding)
    x = centers_x[i0 : i1 + 1]
    y = centers_y[j0 : j1 + 1]
    normalized = density[i0 : i1 + 1, j0 : j1 + 1] / peak
    x_grid, y_grid = np.meshgrid(x, y, indexing="ij")
    heights = course.sample(x_grid, y_grid)[0]
    return {
        "x_m": x.round(6).tolist(),
        "y_m": y.round(6).tolist(),
        "height_m": heights.round(6).tolist(),
        "density": normalized.round(7).tolist(),
    }


def preview(request: dict) -> dict:
    settings, course, club, shot_type, shot_power, aim_deg, modifiers, environment, start_xy = _settings(request)
    sample_count = int(request.get("sample_count", 500))
    preview_seed = int(request.get("preview_seed", 0))
    if not 1 <= sample_count <= 5000:
        raise ValueError("sample_count must be between 1 and 5000")
    # The cache and deterministic regeneration both prevent preview rerolling.
    cache_key = json.dumps(
        [preview_seed, sample_count, settings], sort_keys=True, separators=(",", ":")
    )
    if cache_key in _preview_cache:
        return _preview_cache[cache_key]
    normals = draw_standard_normals(sample_count, np.random.default_rng(preview_seed))
    start_surface = int(course.sample(start_xy[0], start_xy[1])[3])
    lie_modifier = lie_launch_modifier(club, shot_type, start_surface)
    v0, w0, _ = launch_conditions(
        normals,
        club,
        shot_type,
        aim_deg,
        item_modifiers=modifiers,
        lie_modifier=lie_modifier,
        shot_power=shot_power,
    )
    result = simulate(
        course,
        v0,
        w0,
        start_xy,
        env=environment,
        dt=0.05,
        keep_paths=PREVIEW_PATH_COUNT,
    )
    aim_radians = np.radians(aim_deg)
    aim_xy = start_xy + 300.0 * np.array(
        [np.cos(aim_radians), -np.sin(aim_radians)]
    )
    response = {
        "grid": _fog_grid(course, result),
        "preview_paths_xyz_m": [path.round(5).tolist() for path in result.paths],
        "statistics": shot_statistics(result, start_xy, aim_xy),
        "sample_count": sample_count,
        "lie": SURFACES[start_surface],
    }
    _preview_cache[cache_key] = response
    return response


def shoot(request: dict) -> dict:
    _, course, club, shot_type, shot_power, aim_deg, modifiers, environment, start_xy = _settings(request)
    shot_seed = int(request["shot_seed"])
    normals = draw_standard_normals(1, np.random.default_rng(shot_seed))
    start_surface = int(course.sample(start_xy[0], start_xy[1])[3])
    lie_modifier = lie_launch_modifier(club, shot_type, start_surface)
    v0, w0, launch = launch_conditions(
        normals,
        club,
        shot_type,
        aim_deg,
        item_modifiers=modifiers,
        lie_modifier=lie_modifier,
        shot_power=shot_power,
    )
    sample_dt_s = 0.02
    result = simulate(
        course, v0, w0, start_xy, env=environment, dt=sample_dt_s, keep_paths=1
    )
    return {
        "sample_dt_s": sample_dt_s,
        "positions_xyz_m": result.paths[0].round(6).tolist(),
        "phases": result.path_phases[0].tolist(),
        "launch": {key: float(value[0]) for key, value in launch.items()},
        "rest_xy_m": result.rest[0].round(6).tolist(),
        "relief_xy_m": result.relief[0].round(6).tolist(),
        "status": int(result.status[0]),
        "surface": int(result.surface[0]),
        "lie": SURFACES[start_surface],
    }


def send(message: dict) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> None:
    send({"type": "ready", "protocol_version": PROTOCOL_VERSION})
    for line in sys.stdin:
        try:
            request = json.loads(line)
            request_type = request.get("type")
            if request_type == "shutdown":
                send({"type": "shutdown_ack"})
                return
            if request.get("protocol_version") != PROTOCOL_VERSION:
                raise ValueError("protocol version mismatch")
            if request_type == "preview":
                payload = preview(request)
            elif request_type == "shoot":
                payload = shoot(request)
            else:
                raise ValueError(f"unknown request type: {request_type}")
            send(
                {
                    "type": request_type,
                    "request_id": request["request_id"],
                    "payload": payload,
                }
            )
        except Exception as exc:
            send(
                {
                    "type": "error",
                    "request_id": request.get("request_id") if "request" in locals() else None,
                    "message": str(exc),
                }
            )


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, EOFError, KeyboardInterrupt):
        pass
