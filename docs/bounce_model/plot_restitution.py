"""Plot the current normal and tangential bounce restitution model."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


OUT_DIR = Path(__file__).resolve().parent


def main():
    speed = np.linspace(0.0, 30.0, 301)
    surfaces = {
    "Green": (0.16, 0.68),
        "Fairway / tee": (0.30, 0.75),
        "Rough": (0.18, 0.50),
        "Bunker": (0.00, 0.00),
    }

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, (ax_e, ax_energy) = plt.subplots(1, 2, figsize=(12, 4.8))

    colors = ("#2ca02c", "#1f77b4", "#5d8739", "#d9a21b")
    for (label, (normal_r, tangent_r)), color in zip(surfaces.items(), colors):
        normal = np.full_like(speed, normal_r)
        tangent = np.full_like(speed, tangent_r)
        ax_e.plot(speed, normal, color=color, lw=2.2, label=f"{label} normal")
        ax_e.plot(speed, tangent, color=color, lw=1.8, ls="--", label=f"{label} tangent")
        ax_energy.plot(
            speed,
            100.0 * normal**2,
            color=color,
            lw=2.2,
            label=f"{label} normal",
        )
        ax_energy.plot(
            speed,
            100.0 * tangent**2,
            color=color,
            lw=1.8,
            ls="--",
            label=f"{label} tangent",
        )

    for ax in (ax_e, ax_energy):
        ax.set_xlim(0.0, 30.0)
        ax.grid(alpha=0.25)
    ax_e.set_ylim(0.0, 0.9)
    ax_e.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_e.set_ylabel("Velocity retained")
    ax_e.set_title("Directional restitution")
    ax_e.legend(fontsize=7, ncol=2)

    ax_energy.set_ylim(0.0, 70.0)
    ax_energy.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_energy.set_ylabel("Component kinetic energy retained (%)")
    ax_energy.set_title("Component energy retention")
    ax_energy.legend(fontsize=7, ncol=2)

    fig.suptitle("Current directional bounce restitution model")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "restitution_vs_normal_speed.png", dpi=180)
    print(f"Wrote {OUT_DIR / 'restitution_vs_normal_speed.png'}")


if __name__ == "__main__":
    main()

