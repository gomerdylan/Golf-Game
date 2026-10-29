"""Interactive physics lab for the golf simulation prototype."""

from __future__ import annotations

import time

import matplotlib.pyplot as plt
import numpy as np
import streamlit as st

from golf_sim import (
    CLUBS,
    SHOT_TYPES,
    Environment,
    ShotModifiers,
    draw_standard_normals,
    launch_conditions,
    make_test_hole,
    plot,
    shot_statistics,
    simulate,
)
from visualization_3d import plot_course_3d


st.set_page_config(page_title="Golf Physics Lab", layout="wide")
st.title("Golf Physics Lab")
st.caption(
    "Explore how player upgrades change a distribution of physics-based golf shots. "
    "The random samples stay fixed while you move the sliders."
)


@st.cache_resource
def load_course(grid_spacing: float):
    return make_test_hole(dx=grid_spacing)


with st.sidebar:
    st.header("Item effects")
    speed_multiplier = st.slider(
        "Ball speed multiplier",
        min_value=0.75,
        max_value=1.50,
        value=1.00,
        step=0.01,
        help="Scales the mean launch speed while preserving relative speed variation.",
    )
    dispersion_multiplier = st.slider(
        "Dispersion multiplier",
        min_value=0.25,
        max_value=2.00,
        value=1.00,
        step=0.05,
        help="Scales every launch-condition standard deviation together. Lower is more consistent.",
    )

    st.header("Shot")
    club_key = st.selectbox("Club", CLUBS, format_func=lambda key: CLUBS[key].name)
    shot_type = st.selectbox("Shot type", SHOT_TYPES)
    aim_direction_deg = st.slider(
        "Aim direction",
        min_value=-15.0,
        max_value=15.0,
        value=0.0,
        step=0.5,
        format="%+.1f°",
        help="Negative aims left; positive aims right. This changes direction, not shot power.",
    )
    st.header("Simulation fidelity")
    physics_timestep = st.select_slider(
        "Physics timestep (s)",
        options=[0.025, 0.05, 0.1, 0.15, 0.25],
        value=0.1,
        help="RK4 integration step. Smaller values are slower and more precise.",
    )
    grid_spacing = st.select_slider(
        "Terrain grid spacing (m)",
        options=[0.5, 1.0, 2.0, 4.0],
        value=1.0,
        help="Distance between terrain samples. Smaller values use a finer course grid.",
    )
    sample_count = st.select_slider(
        "Samples", options=[100, 250, 500, 1000], value=500
    )
    seed = st.number_input("Random seed", min_value=0, value=2, step=1)
    with st.container(border=True):
        st.caption("Performance audit")
        physics_timing_slot = st.empty()
        render_timing_slot = st.empty()
        st.caption("Server-side timings only; browser/WebGL drawing is not measured.")

course = load_course(grid_spacing)
start = np.array([2.0, 0.0])
aim_display_distance = 260.0
aim_radians = np.radians(aim_direction_deg)
aim = start + aim_display_distance * np.array(
    [np.cos(aim_radians), -np.sin(aim_radians)]
)
aim_deg = aim_direction_deg

physics_start = time.perf_counter()
rng = np.random.default_rng(seed)
standard_normals = draw_standard_normals(sample_count, rng)
item_modifiers = ShotModifiers(
    speed_multiplier=speed_multiplier,
    dispersion_multiplier=dispersion_multiplier,
)
v0, w0, _ = launch_conditions(
    standard_normals,
    CLUBS[club_key],
    shot_type,
    aim_deg,
    item_modifiers=item_modifiers,
)
with st.spinner("Simulating shots..."):
    result = simulate(
        course,
        v0,
        w0,
        start,
        env=Environment(),
        dt=physics_timestep,
    )
physics_elapsed = time.perf_counter() - physics_start
physics_timing_slot.metric("Total physics", f"{physics_elapsed * 1000:.1f} ms")
stats = shot_statistics(result, start, aim)

metric_columns = st.columns(3)
shot_metrics = [
    ("Mean carry", f"{stats['carry_mean_yd']:.1f} yd"),
    ("Mean total", f"{stats['total_mean_yd']:.1f} yd"),
    ("Lateral spread", f"{stats['lateral_sd_yd']:.1f} yd"),
]
for column, (label, value) in zip(metric_columns, shot_metrics):
    column.metric(label, value)

outcome_columns = st.columns(6)
outcomes = [
    ("Rough", stats["rough_pct"]),
    ("Fairway", stats["fairway_pct"]),
    ("Green", stats["green_pct"]),
    ("Bunker", stats["bunker_pct"]),
    ("Water", stats["water_pct"]),
    ("Out of bounds", stats["ob_pct"]),
]
for column, (label, value) in zip(outcome_columns, outcomes):
    column.metric(label, f"{value:.1f}%")

st.session_state.setdefault("camera_view", "Isometric")
st.session_state.setdefault("camera_revision", 0)


def reset_camera(view: str):
    st.session_state.camera_view = view
    st.session_state.camera_revision += 1


with st.container(horizontal=True):
    st.button(
        "Isometric view",
        icon=":material/view_in_ar:",
        on_click=reset_camera,
        args=("Isometric",),
    )
    st.button(
        "Top-down view",
        icon=":material/map:",
        on_click=reset_camera,
        args=("Top-down",),
    )

render_start = time.perf_counter()
course_3d = plot_course_3d(
    course,
    result,
    start,
    aim,
    camera_view=st.session_state.camera_view,
    camera_revision=st.session_state.camera_revision,
)
st.plotly_chart(
    course_3d,
    width="stretch",
    height=720,
    theme=None,
    key="course_3d",
    config={"scrollZoom": True, "displaylogo": False},
    alt="Interactive 3D terrain with sample trajectories and landing probability",
)
render_elapsed = time.perf_counter() - render_start
render_timing_slot.metric(
    "Server figure preparation", f"{render_elapsed * 1000:.1f} ms"
)

st.caption(
    "Drag to orbit. Use the mouse wheel to zoom. Double-click to reset to the selected camera view."
)

diagnostics = st.expander("2D diagnostic views", on_change="rerun")
if diagnostics.open:
    with diagnostics:
        diagnostic_title = (
            f"{CLUBS[club_key].name} ({shot_type}), {sample_count} samples — "
            f"speed {speed_multiplier:.2f}×, dispersion {dispersion_multiplier:.2f}×"
        )
        diagnostic_figure = plot(
            course,
            result,
            start,
            aim,
            actual=None,
            title=diagnostic_title,
        )
        st.pyplot(
            diagnostic_figure,
            width="stretch",
            alt="Top-down landing heatmap and side view of sample trajectories",
        )
        plt.close(diagnostic_figure)

