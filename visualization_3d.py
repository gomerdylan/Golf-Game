"""Interactive 3D rendering for the golf physics lab."""

from __future__ import annotations

import numpy as np
import plotly.graph_objects as go

from golf_sim import (
    M_TO_YD,
    OOB_DISPLAY_MARGIN_M,
    OUT_OF_BOUNDS_COLOR,
    SURFACE_COLORS,
    Course,
    Result,
    landing_density,
)


ISOMETRIC_CAMERA = dict(
    eye=dict(x=0.88, y=-0.95, z=0.68),
    up=dict(x=0, y=0, z=1),
)
TOP_DOWN_CAMERA = dict(
    eye=dict(x=0, y=0, z=1.72),
    up=dict(x=0, y=1, z=0),
)

# Plotly renders each surface in a separate WebGL layer. Small, intentional
# separation prevents depth-buffer flicker when the camera is far from the hole.
MATERIAL_LIFT_YD = 0.18
FOG_BASE_LIFT_YD = 1.0
FOG_LAYER_SPACING_YD = 0.65
TRAJECTORY_LIFT_YD = 0.25
AIM_LIFT_YD = 0.65
OOB_SURFACE_DROP_YD = 0.06


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
    render_stride: int | None = None,
    vertical_exaggeration: float = 1.0,
    max_paths: int = 12,
    camera_view: str = "Isometric",
    camera_revision: int = 0,
) -> go.Figure:
    """Render a lightweight display mesh while preserving full-resolution physics."""
    if render_stride is None:
        render_stride = max(1, round(4.0 / course.dx))

    xs = course.x0 + course.dx * np.arange(course.nx)
    ys = course.y0 + course.dx * np.arange(course.ny)
    render_xs = xs[::render_stride]
    render_ys = ys[::render_stride]
    right, downrange = np.meshgrid(-render_ys * M_TO_YD, render_xs * M_TO_YD)
    terrain_height = course.H[::render_stride, ::render_stride] * (
        M_TO_YD * vertical_exaggeration
    )

    figure = go.Figure()
    # A non-playable apron makes the physics boundary visible and gives OOB
    # probability fog somewhere truthful to render. Edge-clamped terrain keeps
    # it visually continuous without extending playable course physics.
    render_spacing = render_stride * course.dx
    apron_xs = np.arange(
        xs.min() - OOB_DISPLAY_MARGIN_M,
        xs.max() + OOB_DISPLAY_MARGIN_M + 0.5 * render_spacing,
        render_spacing,
    )
    apron_ys = np.arange(
        ys.min() - OOB_DISPLAY_MARGIN_M,
        ys.max() + OOB_DISPLAY_MARGIN_M + 0.5 * render_spacing,
        render_spacing,
    )
    apron_x, apron_y = np.meshgrid(apron_xs, apron_ys, indexing="ij")
    apron_height = course.sample(apron_x.ravel(), apron_y.ravel())[0].reshape(
        apron_x.shape
    )
    figure.add_surface(
        x=-apron_y * M_TO_YD,
        y=apron_x * M_TO_YD,
        z=(
            apron_height * M_TO_YD * vertical_exaggeration
            - OOB_SURFACE_DROP_YD
        ),
        surfacecolor=np.zeros_like(apron_height),
        colorscale=[(0.0, OUT_OF_BOUNDS_COLOR), (1.0, OUT_OF_BOUNDS_COLOR)],
        cmin=0,
        cmax=1,
        autocolorscale=False,
        showscale=False,
        lighting=dict(ambient=1.0, diffuse=0.0, roughness=1.0, specular=0.0),
        hovertemplate="Out of bounds<extra></extra>",
        name="Out of bounds",
    )
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
    density_mass = float(density.sum())
    if density_mass:
        focus_course_x = float(np.average(density_x, weights=density.sum(axis=1)))
        focus_course_y = float(np.average(density_y, weights=density.sum(axis=0)))
    else:
        focus_course_x, focus_course_y = np.asarray(aim_xy, dtype=float)

    display_right = -focus_course_y * M_TO_YD
    display_downrange = focus_course_x * M_TO_YD
    right_min, right_max = -apron_ys.max() * M_TO_YD, -apron_ys.min() * M_TO_YD
    downrange_min, downrange_max = apron_xs.min() * M_TO_YD, apron_xs.max() * M_TO_YD
    camera_center = dict(
        x=float(np.clip(
            2 * (display_right - (right_min + right_max) / 2) / (right_max - right_min),
            -0.8,
            0.8,
        )),
        y=float(np.clip(
            2 * (display_downrange - (downrange_min + downrange_max) / 2)
            / (downrange_max - downrange_min),
            -0.8,
            0.8,
        )),
        z=-0.12,
    )
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
        peak_density = float(density.max())
        base_height = ground_height * M_TO_YD * vertical_exaggeration
        # Plotly cannot reliably depth-sort a translucent Surface over another
        # Surface. A layered point cloud reads as probability fog and leaves the
        # course visible without coplanar sheets fighting in the depth buffer.
        for layer_index, density_fraction in enumerate((0.05, 0.25, 0.50, 0.75)):
            layer_mask = local_visible & (
                local_density >= peak_density * density_fraction
            )
            figure.add_scatter3d(
                x=(-sample_y[layer_mask] * M_TO_YD),
                y=(sample_x[layer_mask] * M_TO_YD),
                z=(
                    base_height[layer_mask]
                    + FOG_BASE_LIFT_YD
                    + layer_index * FOG_LAYER_SPACING_YD
                ),
                mode="markers",
                marker=dict(
                    size=6,
                    color=local_density[layer_mask],
                    colorscale="Inferno",
                    cmin=0,
                    cmax=peak_density,
                    opacity=0.30,
                    showscale=False,
                ),
                hoverinfo="skip",
                showlegend=False,
                name="Landing probability fog",
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
    aim_fraction = np.linspace(0.0, 1.0, 80)[:, None]
    aim_line = marker_points[0] + aim_fraction * (marker_points[1] - marker_points[0])
    aim_ground_height = course.sample(aim_line[:, 0], aim_line[:, 1])[0]
    figure.add_scatter3d(
        x=-aim_line[:, 1] * M_TO_YD,
        y=aim_line[:, 0] * M_TO_YD,
        z=aim_ground_height * M_TO_YD * vertical_exaggeration + AIM_LIFT_YD,
        mode="lines",
        line=dict(width=5, color="cyan", dash="dash"),
        hoverinfo="skip",
        showlegend=False,
        name="Aim direction",
    )

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

    camera = {**cameras[camera_view], "center": camera_center}
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
            # Preserve physical proportions: one yard has the same visual scale
            # downrange, sideways, and vertically.
            aspectmode="data",
            camera=camera,
            dragmode="orbit",
        ),
    )
    return figure
