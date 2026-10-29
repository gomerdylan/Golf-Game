"""Interactive 3D rendering for the golf physics lab."""

from __future__ import annotations

import numpy as np
import plotly.graph_objects as go

from golf_sim import M_TO_YD, SURFACE_COLORS, Course, Result, landing_density


ISOMETRIC_CAMERA = dict(
    eye=dict(x=1.25, y=-1.35, z=0.9),
    up=dict(x=0, y=0, z=1),
)
TOP_DOWN_CAMERA = dict(
    eye=dict(x=0, y=0, z=2.5),
    up=dict(x=0, y=1, z=0),
)

# Plotly renders each surface in a separate WebGL layer. Small, intentional
# separation prevents depth-buffer flicker when the camera is far from the hole.
MATERIAL_LIFT_YD = 0.18
DENSITY_LIFT_YD = 0.45
TRAJECTORY_LIFT_YD = 0.25


def _surface_colorscale(colors: list[str]) -> list[tuple[float, str]]:
    """Build hard color boundaries for integer-valued surface codes."""
    scale: list[tuple[float, str]] = []
    for index, color in enumerate(colors):
        left = index / len(colors)
        right = (index + 1) / len(colors)
        scale.append((left, color))
        scale.append((1.0 if index == len(colors) - 1 else right - 1e-6, color))
    return scale


def _add_material_overlay(
    figure: go.Figure,
    course: Course,
    surface_code: int,
    vertical_exaggeration: float,
):
    """Overlay a full-resolution material mask on the coarser terrain mesh."""
    mask = course.S == surface_code
    rows, columns = np.where(mask)
    if not len(rows):
        return
    row_slice = slice(max(rows.min() - 1, 0), min(rows.max() + 2, course.nx))
    column_slice = slice(max(columns.min() - 1, 0), min(columns.max() + 2, course.ny))
    local_mask = mask[row_slice, column_slice]
    local_height = course.H[row_slice, column_slice] * M_TO_YD * vertical_exaggeration
    local_height = np.where(local_mask, local_height + MATERIAL_LIFT_YD, np.nan)
    local_xs = course.x0 + course.dx * np.arange(course.nx)[row_slice]
    local_ys = course.y0 + course.dx * np.arange(course.ny)[column_slice]
    right, downrange = np.meshgrid(-local_ys * M_TO_YD, local_xs * M_TO_YD)
    color = SURFACE_COLORS[surface_code]
    figure.add_surface(
        x=right,
        y=downrange,
        z=local_height,
        surfacecolor=np.zeros_like(local_height),
        colorscale=[(0.0, color), (1.0, color)],
        cmin=0,
        cmax=1,
        autocolorscale=False,
        showscale=False,
        connectgaps=False,
        lighting=dict(ambient=1.0, diffuse=0.0, roughness=1.0, specular=0.0),
        hoverinfo="skip",
        showlegend=False,
    )


def plot_course_3d(
    course: Course,
    result: Result,
    start_xy,
    aim_xy,
    *,
    render_stride: int = 4,
    vertical_exaggeration: float = 3.0,
    max_paths: int = 12,
    camera_view: str = "Isometric",
    camera_revision: int = 0,
) -> go.Figure:
    """Render a lightweight display mesh while preserving full-resolution physics."""
    xs = course.x0 + course.dx * np.arange(course.nx)
    ys = course.y0 + course.dx * np.arange(course.ny)
    render_xs = xs[::render_stride]
    render_ys = ys[::render_stride]
    right, downrange = np.meshgrid(-render_ys * M_TO_YD, render_xs * M_TO_YD)
    terrain_height = course.H[::render_stride, ::render_stride] * (
        M_TO_YD * vertical_exaggeration
    )

    figure = go.Figure()
    # The coarse mesh carries the heightfield and broad rough/fairway materials.
    # Small features are overlaid below at full resolution, like a game-engine
    # material/splat map, so they do not inherit the geometry mesh's block size.
    base_surfaces = course.S[::render_stride, ::render_stride].copy()
    # Put a similar green beneath the detailed green overlay so no rough-colored
    # pixels can peek through along its full-resolution boundary.
    base_surfaces[base_surfaces == 2] = 1
    base_surfaces[base_surfaces >= 3] = 0
    figure.add_surface(
        x=right,
        y=downrange,
        z=terrain_height,
        surfacecolor=base_surfaces,
        colorscale=_surface_colorscale(SURFACE_COLORS),
        cmin=-0.5,
        cmax=len(SURFACE_COLORS) - 0.5,
        autocolorscale=False,
        showscale=False,
        # Flat lighting preserves the same categorical colors as the 2D map.
        lighting=dict(ambient=1.0, diffuse=0.0, roughness=1.0, specular=0.0),
        hovertemplate="Right %{x:.0f} yd<br>Downrange %{y:.0f} yd<extra></extra>",
        name="Course",
    )

    for surface_code in (2, 3, 4):
        _add_material_overlay(figure, course, surface_code, vertical_exaggeration)

    # Project the exact same 2 m histogram and 1.5-cell Gaussian kernel used by
    # the 2D heatmap onto the terrain.
    density_x, density_y, density, visible = landing_density(course, result)
    visible_rows, visible_columns = np.where(visible)
    if len(visible_rows):
        row_slice = slice(visible_rows.min(), visible_rows.max() + 1)
        column_slice = slice(visible_columns.min(), visible_columns.max() + 1)
        local_x = density_x[row_slice]
        local_y = density_y[column_slice]
        local_density = density[row_slice, column_slice]
        local_visible = visible[row_slice, column_slice]
        sample_x, sample_y = np.meshgrid(local_x, local_y, indexing="ij")
        ground_height = course.sample(sample_x.ravel(), sample_y.ravel())[0].reshape(
            sample_x.shape
        )
        density_height = (
            ground_height * M_TO_YD * vertical_exaggeration + DENSITY_LIFT_YD
        )
        density_height = np.where(local_visible, density_height, np.nan)
        figure.add_surface(
            x=-sample_y * M_TO_YD,
            y=sample_x * M_TO_YD,
            z=density_height,
            surfacecolor=local_density,
            colorscale="Inferno",
            cmin=0,
            cmax=float(density.max()),
            autocolorscale=False,
            # Transparent Plotly surfaces can sort incorrectly against another
            # 3D surface. Inferno already encodes probability intensity, so an
            # opaque layer is both clearer and more stable.
            opacity=1.0,
            showscale=False,
            connectgaps=False,
            lighting=dict(ambient=1.0, diffuse=0.0, specular=0.0),
            hoverinfo="skip",
            name="Landing probability",
        )

    for index, path in enumerate(result.paths[:max_paths]):
        ground_height = course.sample(path[:, 0], path[:, 1])[0]
        height_above_ground = path[:, 2] - ground_height
        display_height = (
            ground_height * vertical_exaggeration + height_above_ground
        ) * M_TO_YD + TRAJECTORY_LIFT_YD
        figure.add_scatter3d(
            x=-path[:, 1] * M_TO_YD,
            y=path[:, 0] * M_TO_YD,
            z=display_height,
            mode="lines",
            line=dict(width=3, color="rgba(95,95,95,0.78)"),
            hoverinfo="skip",
            showlegend=False,
            name=f"Trajectory {index + 1}",
        )

    marker_points = np.asarray([start_xy, aim_xy], dtype=float)
    marker_height = course.sample(marker_points[:, 0], marker_points[:, 1])[0]
    figure.add_scatter3d(
        x=-marker_points[:, 1] * M_TO_YD,
        y=marker_points[:, 0] * M_TO_YD,
        z=marker_height * M_TO_YD * vertical_exaggeration + 1.0,
        mode="markers+text",
        marker=dict(size=[7, 8], color=["white", "cyan"], line=dict(width=1, color="black")),
        text=["Tee", "Aim"],
        textposition="top center",
        hoverinfo="skip",
        showlegend=False,
    )

    cameras = {"Isometric": ISOMETRIC_CAMERA, "Top-down": TOP_DOWN_CAMERA}
    if camera_view not in cameras:
        raise ValueError(f"unknown camera view: {camera_view}")

    camera_uirevision = f"course-camera-{camera_revision}"
    figure.update_layout(
        # Preserve client-side camera/orbit state when Streamlit sends updated
        # shot data after a widget rerun. Change this token only when a future
        # layout change should intentionally reset the view.
        uirevision=camera_uirevision,
        height=650,
        margin=dict(l=0, r=0, t=40, b=0),
        title=dict(text="Interactive 3D view", x=0.5),
        showlegend=False,
        scene=dict(
            uirevision=camera_uirevision,
            xaxis_title="Right (yd)",
            yaxis_title="Downrange (yd)",
            zaxis_title="Height (yd)",
            aspectmode="manual",
            aspectratio=dict(x=0.55, y=1.8, z=0.45),
            camera=cameras[camera_view],
            dragmode="orbit",
        ),
    )
    return figure
