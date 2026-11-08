"""Engine-neutral semantic course descriptions and raster compilation.

CourseSpec is the authoring/procedural boundary.  Physics and rendering may
bake it at different resolutions, but neither owns a separate hole design.
All distances and heights are meters.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
import json
from pathlib import Path

import numpy as np


SURFACE_IDS = {"rough": 0, "fairway": 1, "green": 2, "bunker": 3, "water": 4, "tee": 5}


@dataclass(frozen=True)
class BoundsSpec:
    x_min: float
    x_max: float
    y_min: float
    y_max: float


@dataclass(frozen=True)
class TerrainSpec:
    rise_per_m: float = 0.004
    hill_amplitude_m: float = 2.4
    hill_x_period_m: float = 160.0
    hill_y_period_m: float = 110.0


@dataclass(frozen=True)
class FairwaySpec:
    centerline_xy_m: tuple[tuple[float, float], ...]
    half_width_m: float
    x_start_m: float
    x_end_m: float


@dataclass(frozen=True)
class EllipseSpec:
    surface: str
    center_xy_m: tuple[float, float]
    radii_xy_m: tuple[float, float]


@dataclass(frozen=True)
class RectangleSpec:
    surface: str
    x_range_m: tuple[float, float]
    y_range_m: tuple[float, float]


@dataclass(frozen=True)
class GreenSpec:
    center_xy_m: tuple[float, float]
    radii_xy_m: tuple[float, float]
    transition_width_m: float = 8.0
    grade_x: float = 0.02
    ridge_height_m: float = 0.25
    ridge_width_m: float = 3.0


@dataclass(frozen=True)
class CourseSpec:
    name: str
    bounds: BoundsSpec
    terrain: TerrainSpec
    tee_xy_m: tuple[float, float]
    cup_xy_m: tuple[float, float]
    fairways: tuple[FairwaySpec, ...] = field(default_factory=tuple)
    greens: tuple[GreenSpec, ...] = field(default_factory=tuple)
    ellipses: tuple[EllipseSpec, ...] = field(default_factory=tuple)
    rectangles: tuple[RectangleSpec, ...] = field(default_factory=tuple)

    def to_json(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(asdict(self), indent=2) + "\n", encoding="utf-8")

    @classmethod
    def from_json(cls, path: str | Path) -> "CourseSpec":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return cls(
            name=data["name"],
            bounds=BoundsSpec(**data["bounds"]),
            terrain=TerrainSpec(**data["terrain"]),
            tee_xy_m=tuple(data["tee_xy_m"]),
            cup_xy_m=tuple(data["cup_xy_m"]),
            fairways=tuple(FairwaySpec(tuple(map(tuple, f.pop("centerline_xy_m"))), **f) for f0 in data.get("fairways", []) for f in [dict(f0)]),
            greens=tuple(GreenSpec(tuple(g.pop("center_xy_m")), tuple(g.pop("radii_xy_m")), **g) for g0 in data.get("greens", []) for g in [dict(g0)]),
            ellipses=tuple(EllipseSpec(e.pop("surface"), tuple(e.pop("center_xy_m")), tuple(e.pop("radii_xy_m"))) for e0 in data.get("ellipses", []) for e in [dict(e0)]),
            rectangles=tuple(RectangleSpec(r.pop("surface"), tuple(r.pop("x_range_m")), tuple(r.pop("y_range_m"))) for r0 in data.get("rectangles", []) for r in [dict(r0)]),
        )


def test_hole_spec() -> CourseSpec:
    points = tuple((float(x), float(8.0 * np.sin(x / 110.0))) for x in range(0, 421, 35))
    return CourseSpec(
        name="test_hole",
        bounds=BoundsSpec(0.0, 420.0, -60.0, 60.0),
        terrain=TerrainSpec(),
        tee_xy_m=(5.0, 0.0),
        cup_xy_m=(385.0, -5.0),
        fairways=(FairwaySpec(points, 16.0, 170.0, 360.0),),
        greens=(GreenSpec((385.0, -5.0), (18.0, 13.0)),),
        ellipses=(
            EllipseSpec("bunker", (368.0, 15.0), (7.0, 7.0)),
            # Oversized mid-hole bunker provides a convenient target for
            # repeatedly testing sand impact, skid, and roll behavior.
            EllipseSpec("bunker", (262.0, -20.0), (18.0, 14.0)),
        ),
        rectangles=(
            RectangleSpec("tee", (0.0, 12.0), (-6.0, 6.0)),
            RectangleSpec("water", (215.0, 245.0), (22.0, 50.0)),
        ),
    )


def water_carry_hole_spec() -> CourseSpec:
    """A longer dogleg whose first strategic question is a forced water carry."""
    return CourseSpec(
        name="water_carry",
        bounds=BoundsSpec(0.0, 700.0, -120.0, 120.0),
        terrain=TerrainSpec(rise_per_m=0.002, hill_amplitude_m=4.0),
        tee_xy_m=(5.0, 0.0),
        cup_xy_m=(650.0, 70.0),
        fairways=(
            FairwaySpec(
                ((0.0, 0.0), (150.0, 0.0), (300.0, 35.0), (475.0, 80.0), (650.0, 70.0)),
                22.0,
                10.0,
                625.0,
            ),
        ),
        greens=(GreenSpec((650.0, 70.0), (22.0, 16.0)),),
        ellipses=(EllipseSpec("bunker", (620.0, 45.0), (12.0, 7.0)),),
        rectangles=(
            RectangleSpec("tee", (0.0, 12.0), (-6.0, 6.0)),
            # Rectangles are painted after fairways, so this is a real forced
            # carry rather than fairway drawn on top of the hazard.
            RectangleSpec("water", (220.0, 310.0), (-70.0, 90.0)),
        ),
    )


def rasterize_course_spec(spec: CourseSpec, spacing_m: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    if spacing_m <= 0:
        raise ValueError("course grid spacing must be greater than zero")
    b = spec.bounds
    xs = np.arange(b.x_min, b.x_max + 0.5 * spacing_m, spacing_m)
    ys = np.arange(b.y_min, b.y_max + 0.5 * spacing_m, spacing_m)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    t = spec.terrain
    H = t.rise_per_m * X + t.hill_amplitude_m * np.sin(2 * np.pi * X / t.hill_x_period_m) * np.cos(2 * np.pi * Y / t.hill_y_period_m)
    S = np.full(X.shape, SURFACE_IDS["rough"], dtype=np.uint8)

    for fairway in spec.fairways:
        points = np.asarray(fairway.centerline_xy_m)
        center_y = np.interp(X[:, 0], points[:, 0], points[:, 1])[:, None]
        mask = (X > fairway.x_start_m) & (X < fairway.x_end_m) & (np.abs(Y - center_y) < fairway.half_width_m)
        S[mask] = SURFACE_IDS["fairway"]

    for green in spec.greens:
        gx, gy = green.center_xy_m
        rx, ry = green.radii_xy_m
        radial = np.sqrt(((X - gx) / rx) ** 2 + ((Y - gy) / ry) ** 2)
        S[radial < 1.0] = SURFACE_IDS["green"]
        center_base = t.rise_per_m * gx + t.hill_amplitude_m * np.sin(2 * np.pi * gx / t.hill_x_period_m) * np.cos(2 * np.pi * gy / t.hill_y_period_m)
        target = center_base + green.grade_x * (X - gx) + green.ridge_height_m * np.tanh((Y - gy) / green.ridge_width_m)
        outside_distance = np.maximum(radial - 1.0, 0.0) * min(rx, ry)
        blend = np.clip(1.0 - outside_distance / green.transition_width_m, 0.0, 1.0)
        blend = blend * blend * (3.0 - 2.0 * blend)
        H = H * (1.0 - blend) + target * blend

    for feature in spec.ellipses:
        cx, cy = feature.center_xy_m
        rx, ry = feature.radii_xy_m
        S[((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 < 1.0] = SURFACE_IDS[feature.surface]
    for feature in spec.rectangles:
        S[(X > feature.x_range_m[0]) & (X < feature.x_range_m[1]) & (Y > feature.y_range_m[0]) & (Y < feature.y_range_m[1])] = SURFACE_IDS[feature.surface]
    return xs, ys, H, S
