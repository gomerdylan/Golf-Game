"""Generate the explanatory figures for docs/crater_model/README.md."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


V0_MPS = 18.6
PHI0_DEG = 44.4
THETA0_DEG = 15.4
OUT_DIR = Path(__file__).resolve().parent


def penner_angle(speed_mps, impact_deg):
    """Penner's unbounded first-order extrapolation, in degrees."""
    return THETA0_DEG * np.asarray(speed_mps) / V0_MPS * np.asarray(impact_deg) / PHI0_DEG


def component_angle(speed_mps, impact_deg, speed_exponent):
    """Boundary-constrained family with an explicit unknown speed exponent."""
    phi = np.deg2rad(np.asarray(impact_deg))
    phi0 = np.deg2rad(PHI0_DEG)
    angular_factor = np.sin(2.0 * phi) ** 2 / np.sin(2.0 * phi0) ** 2
    ratio = (np.asarray(speed_mps) / V0_MPS) ** speed_exponent * angular_factor
    impulse_ratio = np.tan(np.deg2rad(THETA0_DEG)) * ratio
    return np.rad2deg(np.arctan(impulse_ratio))


def add_model_curves(ax, x, penner_y, component_y):
    ax.plot(x, penner_y, color="#d62728", lw=2.3, label="Penner")
    styles = ((0, "#2ca02c", "-"), (1, "#1f77b4", "--"), (2, "#9467bd", ":"))
    for exponent, color, style in styles:
        ax.plot(x, component_y(exponent), color=color, lw=2.0, ls=style, label=rf"component model, $p={exponent}$")


def plot_angular_dependence():
    phi = np.linspace(0.0, 90.0, 721)
    speeds = (10.0, V0_MPS, 30.0, 50.0)
    fig, axes = plt.subplots(2, 2, figsize=(11, 7.5), sharex=True, sharey=True)
    for ax, speed in zip(axes.flat, speeds):
        add_model_curves(ax, phi, penner_angle(speed, phi), lambda p: component_angle(speed, phi, p))
        ax.axvline(PHI0_DEG, color="0.75", lw=1, ls=":")
        ax.axhline(0.0, color="0.7", lw=0.8)
        ax.set_ylim(0.0, 90.0)
        ax.set_title(f"Impact speed = {speed:g} m/s")
        ax.grid(alpha=0.2)
    axes[0, 1].scatter(
        [PHI0_DEG],
        [THETA0_DEG],
        color="black",
        zorder=5,
        label="calibration point",
    )
    for ax in axes[-1, :]:
        ax.set_xlabel(r"Impact angle from surface normal, $\phi$ (deg)")
    for ax in axes[:, 0]:
        ax.set_ylabel(r"Effective crater angle, $\theta_c$ (deg)")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    calibration = axes[0, 1].get_legend_handles_labels()
    axes[0, 0].legend(
        handles + calibration[0][-1:],
        labels + calibration[1][-1:],
        fontsize=8,
        loc="upper left",
    )
    fig.suptitle("Angular dependence: Penner vs component-constrained hypotheses")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "angular_dependence.png", dpi=180)
    plt.close(fig)


def plot_speed_dependence():
    speed = np.linspace(0.01, 120.0, 800)
    angles = (15.0, PHI0_DEG, 75.0, 89.0)
    fig, axes = plt.subplots(2, 2, figsize=(11, 7.5), sharex=True, sharey=True)
    for ax, phi in zip(axes.flat, angles):
        add_model_curves(ax, speed, penner_angle(speed, phi), lambda p: component_angle(speed, phi, p))
        ax.axvline(V0_MPS, color="0.75", lw=1, ls=":")
        ax.set_ylim(0.0, 90.0)
        ax.set_title(rf"Fixed incidence $\phi={phi:g}^\circ$")
        ax.grid(alpha=0.2)
    for ax in axes[-1, :]:
        ax.set_xlabel("Impact speed (m/s)")
    for ax in axes[:, 0]:
        ax.set_ylabel(r"Effective crater angle, $\theta_c$ (deg)")
    axes[0, 0].legend(fontsize=8, loc="upper left")
    fig.suptitle("Speed dependence at fixed impact angle: the exponent is unknown")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "speed_dependence.png", dpi=180)
    plt.close(fig)


def plot_velocity_components():
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.8))
    cases = ((0.0, "Normal impact"), (45.0, "Oblique impact"), (88.0, "Grazing limit"))
    for ax, (phi_deg, title) in zip(axes, cases):
        phi = np.deg2rad(phi_deg)
        vt, vn = np.sin(phi), np.cos(phi)
        ax.axhline(0, color="0.25", lw=2)
        ax.arrow(0, 1, vt, -vn, width=0.012, head_width=0.09, length_includes_head=True, color="#222222")
        ax.arrow(0, 1, vt, 0, width=0.008, head_width=0.07, length_includes_head=True, color="#d62728")
        ax.arrow(vt, 1, 0, -vn, width=0.008, head_width=0.07, length_includes_head=True, color="#1f77b4")
        ax.text(vt / 2, 1.07, r"$v_t$", color="#d62728", ha="center")
        ax.text(vt + 0.05, 1 - vn / 2, r"$v_n$", color="#1f77b4", va="center")
        ax.set_title(
            f"{title}\n$\\phi={phi_deg:g}^\\circ$,  "
            f"$(v_t v_n)^2={(vt * vn) ** 2:.3f}\\,v^4$"
        )
        ax.set_xlim(-0.15, 1.2)
        ax.set_ylim(-0.15, 1.25)
        ax.set_aspect("equal")
        ax.axis("off")
    fig.suptitle("Implemented asymmetry vanishes quadratically without motion or penetration")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "velocity_components.png", dpi=180, bbox_inches="tight")
    plt.close(fig)


def plot_effective_plane_geometry():
    theta = np.deg2rad(28.0)
    fig, ax = plt.subplots(figsize=(9, 5.2))
    x = np.linspace(-2.4, 2.4, 100)
    ax.plot(x, np.zeros_like(x), color="0.55", lw=2, ls="--", label="undeformed ground")
    ax.plot(x, np.tan(theta) * x, color="#8c564b", lw=4, label="effective plane")
    impulse = 1.55 * np.array([-np.sin(theta), np.cos(theta)])
    normal_part = np.array([0.0, impulse[1]])
    tangent_part = np.array([impulse[0], 0.0])
    ax.arrow(0, 0, *impulse, width=0.025, head_width=0.13, length_includes_head=True, color="#222222")
    ax.arrow(0, 0, *normal_part, width=0.014, head_width=0.10, length_includes_head=True, color="#1f77b4")
    ax.arrow(*normal_part, *tangent_part, width=0.014, head_width=0.10, length_includes_head=True, color="#d62728")
    ax.text(impulse[0] - 0.12, impulse[1] + 0.08, r"resultant $\mathbf{J}$", ha="right")
    ax.text(0.08, normal_part[1] / 2, r"$J_n$", color="#1f77b4")
    ax.text(tangent_part[0] / 2, normal_part[1] + 0.08, r"$J_t$", color="#d62728", ha="center")
    arc = np.linspace(np.pi / 2, np.pi / 2 + theta, 50)
    ax.plot(0.42 * np.cos(arc), 0.42 * np.sin(arc), color="black", lw=1.5)
    ax.text(-0.20, 0.48, r"$\theta_c$", ha="center")
    ax.text(-2.25, 1.55, r"$\tan\theta_c=J_t/J_n$", fontsize=14)
    ax.text(-2.25, 1.30, "Impulse direction, not rebound direction", fontsize=11)
    ax.set_xlim(-2.5, 2.5)
    ax.set_ylim(-1.35, 1.9)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "effective_plane_geometry.png", dpi=180, bbox_inches="tight")
    plt.close(fig)


def main():
    plt.style.use("seaborn-v0_8-whitegrid")
    plot_angular_dependence()
    plot_speed_dependence()
    plot_velocity_components()
    plot_effective_plane_geometry()
    print(f"Wrote crater-model figures to {OUT_DIR}")


if __name__ == "__main__":
    main()

