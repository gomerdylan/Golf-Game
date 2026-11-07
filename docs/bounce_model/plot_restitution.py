"""Plot the current normal coefficient-of-restitution model."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


OUT_DIR = Path(__file__).resolve().parent


def fitted_quadratic(normal_speed_mps):
    speed = np.asarray(normal_speed_mps)
    return 0.510 - 0.0375 * speed + 0.000903 * speed**2


def implemented_base_restitution(normal_speed_mps):
    speed = np.asarray(normal_speed_mps)
    return np.where(speed <= 20.0, fitted_quadratic(speed), 0.120)


def main():
    speed = np.linspace(0.0, 100.0, 1001)
    base = implemented_base_restitution(speed)
    raw_fit = fitted_quadratic(speed)
    surfaces = {
        "Green (0.80x velocity)": 0.80,
        "Fairway / tee (0.70x velocity)": 0.70,
        "Rough (0.45x velocity)": 0.45,
        "Bunker (0.15x velocity)": 0.15,
    }

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, (ax_e, ax_energy) = plt.subplots(1, 2, figsize=(12, 4.8))

    ax_e.plot(
        speed,
        raw_fit,
        color="0.65",
        ls="--",
        lw=1.8,
        label="raw quadratic extrapolation (not used)",
    )
    colors = ("#2ca02c", "#1f77b4", "#5d8739", "#d9a21b")
    for (label, multiplier), color in zip(surfaces.items(), colors):
        final_e = multiplier * base
        ax_e.plot(speed, final_e, color=color, lw=2.2, label=label)
        ax_energy.plot(
            speed,
            100.0 * final_e**2,
            color=color,
            lw=2.2,
            label=label,
        )

    for ax in (ax_e, ax_energy):
        ax.axvline(20.0, color="black", ls=":", lw=1.2)
        ax.set_xlim(0.0, 100.0)
        ax.grid(alpha=0.25)
    ax_e.set_ylim(0.0, 0.65)
    ax_e.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_e.set_ylabel(r"Final coefficient of restitution $e$")
    ax_e.set_title("Implemented restitution curve")
    ax_e.legend(fontsize=8)

    ax_energy.set_ylim(0.0, 28.0)
    ax_energy.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_energy.set_ylabel("Normal kinetic energy retained (%)")
    ax_energy.set_title(r"Normal rebound energy fraction $e^2$")
    ax_energy.legend(fontsize=8)

    fig.suptitle("Current golf-ball turf restitution model")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "restitution_vs_normal_speed.png", dpi=180)
    print(f"Wrote {OUT_DIR / 'restitution_vs_normal_speed.png'}")


if __name__ == "__main__":
    main()

