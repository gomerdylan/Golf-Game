"""Record the rejected capture-law comparison against the former Penner model."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


OUT_DIR = Path(__file__).resolve().parent


def former_penner_fairway_restitution(normal_speed_mps):
    speed = np.asarray(normal_speed_mps)
    penner = np.where(
        speed <= 20.0,
        0.510 - 0.0375 * speed + 0.000903 * speed**2,
        0.120,
    )
    return 0.55 * penner


def capture_restitution(normal_speed_mps, e_infinity, capture_speed_mps):
    speed = np.asarray(normal_speed_mps)
    energy_fraction = np.maximum(
        1.0 - (capture_speed_mps / np.maximum(speed, 1e-12)) ** 2,
        0.0,
    )
    return e_infinity * np.sqrt(energy_fraction)


def main():
    speed = np.linspace(0.05, 30.0, 1200)
    current = former_penner_fairway_restitution(speed)
    proposals = {
        r"$v_c=1$ m/s (rejected trial)": capture_restitution(speed, 0.30, 1.0),
        r"$v_c=4$ m/s": capture_restitution(speed, 0.30, 4.0),
        r"$v_c=6$ m/s": capture_restitution(speed, 0.30, 6.0),
    }

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, (ax_e, ax_energy) = plt.subplots(1, 2, figsize=(12, 4.8))
    ax_e.plot(speed, current, color="black", lw=2.5, label="former Penner fairway")
    ax_energy.plot(
        speed,
        100.0 * current**2,
        color="black",
        lw=2.5,
        label="former Penner fairway",
    )

    colors = ("#2ca02c", "#1f77b4", "#d62728")
    for (label, proposed), color in zip(proposals.items(), colors):
        ax_e.plot(speed, proposed, color=color, lw=2.2, label=label)
        ax_energy.plot(
            speed,
            100.0 * proposed**2,
            color=color,
            lw=2.2,
            label=label,
        )

    for ax in (ax_e, ax_energy):
        ax.axvline(0.5, color="0.4", ls=":", lw=1.3, label="skid threshold")
        ax.set_xlim(0.0, 30.0)
        ax.grid(alpha=0.25)
        ax.legend(fontsize=8)
    ax_e.set_ylim(0.0, 0.34)
    ax_e.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_e.set_ylabel(r"Coefficient of restitution $e$")
    ax_e.set_title("Rebound velocity fraction")

    ax_energy.set_ylim(0.0, 11.0)
    ax_energy.set_xlabel(r"Effective-normal impact speed $|v_n|$ (m/s)")
    ax_energy.set_ylabel("Normal kinetic energy retained (%)")
    ax_energy.set_title(r"Rebound energy fraction $e^2$")

    fig.suptitle(
        r"Fairway capture-law comparison: $e_\infty=0.30$; vary capture speed $v_c$"
    )
    fig.tight_layout()
    output = OUT_DIR / "capture_restitution_proposal.png"
    fig.savefig(output, dpi=180)
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
