"""Interactive physics lab for the golf simulation prototype."""

from __future__ import annotations

import time

import matplotlib.pyplot as plt
import numpy as np
import streamlit as st

from golf_sim import (
    CLUBS,
    MPH,
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


ITEM_EFFECT_DEFAULTS = {
    "effect_speed_multiplier": 1.0,
    "effect_launch_angle_offset": 0.0,
    "effect_spin_multiplier": 1.0,
    "effect_spin_axis_offset": 0.0,
    "effect_global_dispersion": 1.0,
    "effect_start_direction_dispersion": 1.0,
    "effect_spin_axis_dispersion": 1.0,
    "effect_spin_decay": 20.0,
    "effect_magnus_lift": 1.0,
    "effect_air_density": 1.0,
    "effect_wind_speed": 0.0,
    "effect_wind_direction": 0.0,
    "effect_drag": 1.0,
    "effect_gravity": 1.0,
}


def reset_item_effects():
    for key, value in ITEM_EFFECT_DEFAULTS.items():
        st.session_state[key] = value


for item_effect_key, item_effect_default in ITEM_EFFECT_DEFAULTS.items():
    st.session_state.setdefault(item_effect_key, item_effect_default)


with st.sidebar:
    st.header("Item effects")
    st.caption("Launch")
    speed_multiplier = st.slider(
        "Ball speed multiplier",
        min_value=0.75,
        max_value=1.50,
        step=0.01,
        key="effect_speed_multiplier",
        help="Scales the mean launch speed while preserving relative speed variation.",
    )
    launch_angle_offset_deg = st.slider(
        "Launch-angle offset (deg)",
        min_value=-12.0,
        max_value=20.0,
        step=1.0,
        format="%+.0f°",
        key="effect_launch_angle_offset",
        help="Adds to the club and shot type's mean vertical launch angle.",
    )
    spin_multiplier = st.slider(
        "Spin multiplier",
        min_value=0.0,
        max_value=3.0,
        step=0.05,
        key="effect_spin_multiplier",
        help="Scales mean spin and its absolute variation together.",
    )
    spin_axis_offset_deg = st.slider(
        "Spin-axis offset (deg)",
        min_value=-45.0,
        max_value=45.0,
        step=1.0,
        format="%+.0f°",
        key="effect_spin_axis_offset",
        help="Negative produces draw/hook curvature; positive produces fade/slice curvature.",
    )

    st.caption("Accuracy")
    dispersion_multiplier = st.slider(
        "Dispersion multiplier",
        min_value=0.25,
        max_value=2.00,
        step=0.05,
        key="effect_global_dispersion",
        help="Scales every launch-condition standard deviation together. Lower is more consistent.",
    )
    start_direction_dispersion_multiplier = st.slider(
        "Start-direction dispersion",
        min_value=0.0,
        max_value=3.0,
        step=0.05,
        key="effect_start_direction_dispersion",
        help="Scales push/pull variation without changing other launch variables.",
    )
    spin_axis_dispersion_multiplier = st.slider(
        "Spin-axis dispersion",
        min_value=0.0,
        max_value=3.0,
        step=0.05,
        key="effect_spin_axis_dispersion",
        help="Scales hook/slice variation without changing mean shot shape.",
    )

    st.caption("Flight")
    spin_decay_tau = st.slider(
        "Spin-decay time (s)",
        min_value=1.0,
        max_value=120.0,
        step=1.0,
        key="effect_spin_decay",
        help="Larger values preserve spin and its aerodynamic effects for longer.",
    )
    magnus_lift_multiplier = st.slider(
        "Magnus-lift multiplier",
        min_value=0.0,
        max_value=5.0,
        step=0.1,
        key="effect_magnus_lift",
        help="Scales aerodynamic lift and curvature caused by spin.",
    )

    st.caption("Environment")
    air_density_multiplier = st.slider(
        "Air-density multiplier",
        min_value=0.0,
        max_value=2.0,
        step=0.05,
        key="effect_air_density",
        help="Scales both aerodynamic drag and Magnus lift. At 0×, flight occurs in a vacuum.",
    )
    wind_speed_mph = st.slider(
        "Wind speed (mph)",
        min_value=0.0,
        max_value=40.0,
        step=1.0,
        key="effect_wind_speed",
        help="Wind speed relative to the course.",
    )
    wind_direction_deg = st.slider(
        "Wind direction (deg)",
        min_value=-180.0,
        max_value=180.0,
        step=5.0,
        format="%+.0f°",
        key="effect_wind_direction",
        help="Direction the wind blows toward: 0° downrange, +90° right, and 180° headwind.",
    )
    drag_multiplier = st.slider(
        "Drag multiplier",
        min_value=0.0,
        max_value=3.0,
        step=0.05,
        key="effect_drag",
        help="Scales aerodynamic drag without directly changing Magnus lift.",
    )
    gravity_multiplier = st.slider(
        "Gravity multiplier",
        min_value=0.1,
        max_value=3.0,
        step=0.05,
        key="effect_gravity",
        help="Scales gravity consistently during flight and rolling.",
    )
    st.button(
        "Reset item effects",
        icon=":material/restart_alt:",
        on_click=reset_item_effects,
        width="stretch",
    )

    st.header("Shot")
    club_key = st.selectbox("Club", CLUBS, format_func=lambda key: CLUBS[key].name)
    shot_type = st.selectbox("Shot type", SHOT_TYPES)
    aim_direction_deg = st.slider(
        "Aim direction",
        min_value=-30.0,
        max_value=30.0,
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
    launch_angle_offset_deg=launch_angle_offset_deg,
    spin_multiplier=spin_multiplier,
    spin_axis_offset_deg=spin_axis_offset_deg,
    start_direction_dispersion_multiplier=start_direction_dispersion_multiplier,
    spin_axis_dispersion_multiplier=spin_axis_dispersion_multiplier,
)
v0, w0, _ = launch_conditions(
    standard_normals,
    CLUBS[club_key],
    shot_type,
    aim_deg,
    item_modifiers=item_modifiers,
)
with st.spinner("Simulating shots..."):
    wind_direction_radians = np.radians(wind_direction_deg)
    wind = wind_speed_mph * MPH * np.array(
        [
            np.cos(wind_direction_radians),
            -np.sin(wind_direction_radians),
            0.0,
        ]
    )
    environment = Environment(
        air_density=1.225 * air_density_multiplier,
        wind=wind,
        spin_decay_tau=spin_decay_tau,
        magnus_lift_multiplier=magnus_lift_multiplier,
        drag_multiplier=drag_multiplier,
        gravity_multiplier=gravity_multiplier,
    )
    result = simulate(
        course,
        v0,
        w0,
        start,
        env=environment,
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

