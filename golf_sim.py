"""
golf_sim.py — Monte Carlo prototype for a tactical, physics-based golf game.

The player chooses a club, a shot type and an aim point. The game samples launch
conditions from a distribution (push/pull, hook/slice, thin/fat, spin variation),
integrates each ball's flight, bounce and roll, and shows a heatmap of where the
ball is likely to finish. The "real" shot is simply one more draw from the same
simulator, so the forecast is honest by construction.

Everything is vectorized across samples: each state variable is an (N, 3) array
and all N trajectories advance together.

Coordinates (right-handed):
    x  downrange (m)
    y  LEFT of the tee line (m)
    z  up (m)
Angles the player sees (aim, start direction, spin axis) are "positive = right",
which is how golfers think; they are converted at the boundary.

Run:
    python golf_sim.py                               # driver off the tee
    python golf_sim.py --club 7iron --start 230 0 --target 385 -5
    python golf_sim.py --shot draw --wind-mph 12 --wind-dir 90
"""

from __future__ import annotations

import argparse
import time
from dataclasses import dataclass, field

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap

# ----------------------------------------------------------------------------
# Units and constants
# ----------------------------------------------------------------------------
G = 9.81                      # m/s^2
M_TO_YD = 1.0936133
MPH = 0.44704                 # mph -> m/s
RPM = 2 * np.pi / 60          # rpm -> rad/s
UP = np.array([0.0, 0.0, 1.0])

FLIGHT, ROLL, DONE = 0, 1, 2
AT_REST, IN_WATER, OUT_OF_BOUNDS = 0, 1, 2


# ----------------------------------------------------------------------------
# Ball, environment, aerodynamics
# ----------------------------------------------------------------------------
@dataclass
class Ball:
    mass: float = 0.04593      # kg (USGA max)
    radius: float = 0.021335   # m (USGA min diameter 42.67 mm)
    inertia_k: float = 0.4     # I = k m r^2 (solid sphere = 0.4)

    @property
    def area(self) -> float:
        return np.pi * self.radius ** 2


@dataclass
class Environment:
    air_density: float = 1.225                       # kg/m^3 (sea level). Denver ~1.0
    wind: np.ndarray = field(default_factory=lambda: np.zeros(3))  # m/s, (x, y, z)
    spin_decay_tau: float = 20.0                     # s, exponential spin decay


def aero_coeffs(S: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Drag and lift coefficients as functions of spin parameter S = r*omega/v.

    Simple fits in the spirit of published wind-tunnel data for dimpled balls
    at golf Reynolds numbers. These are the main knobs for calibrating carry.
    """
    Cd = 0.23 + 0.25 * S
    Cl = np.clip(2.0 * S - 2.0 * S ** 2, 0.0, 0.30)
    # Calibrated so stock shots land near PGA Tour average carries
    # (driver ~270 yd, 7-iron ~170 yd, PW ~126 yd on flat ground, sea level).
    return Cd, Cl


def flight_accel(vel, omega, ball: Ball, env: Environment):
    """Acceleration from gravity, quadratic drag and Magnus lift. Shapes (n, 3)."""
    v_rel = vel - env.wind
    speed = np.linalg.norm(v_rel, axis=1, keepdims=True) + 1e-9
    w = np.linalg.norm(omega, axis=1, keepdims=True)
    S = ball.radius * w / speed
    Cd, Cl = aero_coeffs(S)
    k = 0.5 * env.air_density * ball.area / ball.mass
    a_drag = -k * Cd * speed * v_rel
    w_hat = omega / (w + 1e-9)
    a_lift = k * Cl * speed * np.cross(w_hat, v_rel)
    return a_drag + a_lift - G * UP


# ----------------------------------------------------------------------------
# Course: heightfield + surface types on a regular grid
# ----------------------------------------------------------------------------
# Surface table. Index = surface code stored in the grid.
SURFACES = ["rough", "fairway", "green", "bunker", "water"]
# Bounce follows Penner's turf model (A. R. Penner, "The run of a golf ball",
# Can. J. Phys. 2002): the ball dents the turf, so it bounces off the front wall of
# a small crater whose angle grows with impact speed and steepness. That is why
# steep, high-spin wedges stop or spin back while low, shallow drives run out.
RESTITUTION = np.array([0.70, 1.00, 1.00, 0.25, 0.0])   # multiplier on Penner's e(v)
MU_BOUNCE = np.array([0.50, 0.43, 0.43, 0.70, 0.0])     # sliding friction during impact
CRATER = np.array([1.40, 0.90, 1.00, 2.50, 0.0])        # crater depth vs a typical green (soft > 1)
ROLL_RESIST = np.array([0.30, 0.12, 0.055, 0.90, 0.0])  # rolling deceleration / g (green ~ stimp 10)
SURFACE_COLORS = ["#4f7d3a", "#7fbf4d", "#a6e07a", "#e8d9a0", "#4a90c2"]
ROLL_THRESHOLD = 0.5  # m/s: bounce with smaller normal speed than this -> rolling


class Course:
    """Heights H[i, j] and surface codes S[i, j] at x = x0 + i*dx, y = y0 + j*dx."""

    def __init__(self, x0, y0, dx, H, S):
        self.x0, self.y0, self.dx = x0, y0, dx
        self.H, self.S = H, S
        self.nx, self.ny = H.shape

    def sample(self, x, y):
        """Bilinear height and gradient, nearest surface type, and in-bounds mask."""
        fx = (x - self.x0) / self.dx
        fy = (y - self.y0) / self.dx
        inside = (fx >= 0) & (fx <= self.nx - 1) & (fy >= 0) & (fy <= self.ny - 1)
        i = np.clip(np.floor(fx).astype(int), 0, self.nx - 2)
        j = np.clip(np.floor(fy).astype(int), 0, self.ny - 2)
        tx = np.clip(fx - i, 0, 1)
        ty = np.clip(fy - j, 0, 1)
        h00, h10 = self.H[i, j], self.H[i + 1, j]
        h01, h11 = self.H[i, j + 1], self.H[i + 1, j + 1]
        h = h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty) + h01 * (1 - tx) * ty + h11 * tx * ty
        dhdx = ((h10 - h00) * (1 - ty) + (h11 - h01) * ty) / self.dx
        dhdy = ((h01 - h00) * (1 - tx) + (h11 - h10) * tx) / self.dx
        si = np.clip(np.rint(fx).astype(int), 0, self.nx - 1)
        sj = np.clip(np.rint(fy).astype(int), 0, self.ny - 1)
        surf = self.S[si, sj]
        return h, dhdx, dhdy, surf, inside


def make_test_hole(dx: float = 1.0) -> Course:
    """A ~440-yard par 4 with a gentle dogleg, a pond, two bunkers and a tilted green."""
    if dx <= 0:
        raise ValueError("course grid spacing must be greater than zero")
    xs = np.arange(0, 420 + 0.5 * dx, dx)
    ys = np.arange(-60, 60 + 0.5 * dx, dx)
    X, Y = np.meshgrid(xs, ys, indexing="ij")

    # Terrain: gentle undulation, rising slightly toward the green.
    H = 0.004 * X + 1.2 * np.sin(2 * np.pi * X / 160) * np.cos(2 * np.pi * Y / 110)

    S = np.zeros_like(X, dtype=int)                       # rough everywhere
    centre = 8 * np.sin(X / 110)                          # fairway centreline (dogleg)
    S[(X > 0) & (X < 12) & (np.abs(Y) < 6)] = 1           # tee box
    S[(X > 170) & (X < 360) & (np.abs(Y - centre) < 16)] = 1

    gx, gy = 385.0, -5.0                                  # green centre
    green = ((X - gx) / 18) ** 2 + ((Y - gy) / 13) ** 2 < 1
    S[green] = 2
    # Green tilts back-to-front (~2%) with a small ridge; overwrite the base terrain there.
    base = 0.004 * gx + 1.2 * np.sin(2 * np.pi * gx / 160) * np.cos(
        2 * np.pi * gy / 110
    )
    H[green] = base + 0.02 * (X[green] - gx) + 0.25 * np.tanh((Y[green] - gy) / 3)

    S[(X - 368) ** 2 + (Y - 15) ** 2 < 7 ** 2] = 3        # greenside bunker (left)
    S[(X - 262) ** 2 + (Y + 20) ** 2 < 8 ** 2] = 3        # fairway bunker (right)
    S[(X > 215) & (X < 245) & (Y > 22) & (Y < 50)] = 4    # pond (left)
    return Course(xs[0], ys[0], dx, H, S)


# ----------------------------------------------------------------------------
# Shot model: clubs, shot types, sampling launch conditions
# ----------------------------------------------------------------------------
@dataclass
class Club:
    name: str
    ball_speed: float      # m/s
    launch_deg: float      # vertical launch angle
    spin_rpm: float        # total spin
    # 1-sd dispersion
    sd_speed_frac: float = 0.015
    sd_launch_deg: float = 1.0
    sd_spin_frac: float = 0.08
    sd_start_deg: float = 1.5   # horizontal start direction (push/pull)
    sd_axis_deg: float = 4.0    # spin-axis tilt (hook/slice)
    corr_start_axis: float = 0.4  # open face -> starts right AND curves right


@dataclass(frozen=True)
class ShotModifiers:
    """Player/item modifiers applied to otherwise stock launch conditions."""

    speed_multiplier: float = 1.0
    dispersion_multiplier: float = 1.0

    def __post_init__(self):
        if self.speed_multiplier <= 0:
            raise ValueError("speed_multiplier must be greater than zero")
        if self.dispersion_multiplier < 0:
            raise ValueError("dispersion_multiplier cannot be negative")


# Means roughly follow published PGA Tour launch-monitor averages.
CLUBS = {
    "driver": Club("Driver", 167 * MPH, 10.9, 2686, sd_start_deg=2.0, sd_axis_deg=6.0, sd_spin_frac=0.10),
    "3wood": Club("3-wood", 158 * MPH, 9.2, 3655, sd_start_deg=1.8, sd_axis_deg=5.0),
    "5iron": Club("5-iron", 132 * MPH, 12.1, 5361),
    "7iron": Club("7-iron", 120 * MPH, 16.3, 7097, sd_start_deg=1.3, sd_axis_deg=3.5),
    "pw": Club("Pitching wedge", 102 * MPH, 24.2, 9304, sd_start_deg=1.0, sd_axis_deg=3.0),
}

# Shot types shift the means and scale the dispersion. Add your own here.
SHOT_TYPES = {
    "stock":  dict(),
    "draw":   dict(start_deg=+2.0, axis_deg=-6.0, spin_frac=-0.05),
    "fade":   dict(start_deg=-2.0, axis_deg=+6.0, spin_frac=+0.05),
    "punch":  dict(launch_deg=-4.0, spin_frac=-0.30, speed_frac=-0.10,
                   dispersion_multiplier=0.9),
    "smooth": dict(speed_frac=-0.05, dispersion_multiplier=0.75),
    "full":   dict(speed_frac=+0.04, dispersion_multiplier=1.35),
}

N_SHOT_VARS = 5  # speed, launch, spin, start direction, spin axis


def draw_standard_normals(n: int, rng: np.random.Generator) -> np.ndarray:
    """Independent N(0,1) draws. Keep these fixed while the player adjusts aim
    (common random numbers) so the heatmap moves smoothly instead of flickering."""
    return rng.standard_normal((n, N_SHOT_VARS))


def launch_conditions(
    Z,
    club: Club,
    shot: str,
    aim_deg: float,
    item_modifiers: ShotModifiers | None = None,
):
    """Map standard normals Z (n, 5) to initial velocity and spin vectors.

    aim_deg: heading of the aim line, positive = right of the +x axis.
    Returns v0 (n, 3), w0 (n, 3) and a dict of the sampled shot parameters.
    """
    shot_type_settings = SHOT_TYPES[shot]
    if item_modifiers is None:
        item_modifiers = ShotModifiers()

    shot_type_dispersion_multiplier = shot_type_settings.get(
        "dispersion_multiplier", 1.0
    )
    combined_dispersion_multiplier = (
        shot_type_dispersion_multiplier * item_modifiers.dispersion_multiplier
    )

    # Correlate start direction and spin axis via a Cholesky factor.
    corr = np.eye(N_SHOT_VARS)
    corr[3, 4] = corr[4, 3] = club.corr_start_axis
    Zc = Z @ np.linalg.cholesky(corr).T

    speed = item_modifiers.speed_multiplier * club.ball_speed * (
        1
        + shot_type_settings.get("speed_frac", 0)
        + combined_dispersion_multiplier * club.sd_speed_frac * Zc[:, 0]
    )
    launch = (
        club.launch_deg
        + shot_type_settings.get("launch_deg", 0)
        + combined_dispersion_multiplier * club.sd_launch_deg * Zc[:, 1]
    )
    spin = club.spin_rpm * (
        1
        + shot_type_settings.get("spin_frac", 0)
        + combined_dispersion_multiplier * club.sd_spin_frac * Zc[:, 2]
    )
    start = (
        shot_type_settings.get("start_deg", 0)
        + combined_dispersion_multiplier * club.sd_start_deg * Zc[:, 3]
    )
    axis = (
        shot_type_settings.get("axis_deg", 0)
        + combined_dispersion_multiplier * club.sd_axis_deg * Zc[:, 4]
    )
    spin = np.maximum(spin, 0)

    psi = np.radians(aim_deg + start)                     # heading, positive = right
    th = np.radians(launch)
    d = np.stack([np.cos(psi), -np.sin(psi), np.zeros_like(psi)], axis=1)
    v0 = speed[:, None] * (np.cos(th)[:, None] * d + np.sin(th)[:, None] * UP)

    # Pure backspin axis is d x up; tilting it by +axis makes the ball curve right.
    b = np.cross(d, UP)
    a = np.radians(axis)[:, None]
    w0 = (spin * RPM)[:, None] * (np.cos(a) * b - np.sin(a) * UP)

    params = dict(speed=speed, launch=launch, spin=spin, start=start, axis=axis)
    return v0, w0, params


# ----------------------------------------------------------------------------
# Ground interaction
# ----------------------------------------------------------------------------
def bounce(vel, omega, dhdx, dhdy, surf, ball: Ball):
    """Impulsive bounce on sloped, deformable turf with spin-dependent friction.

    1. Tilt the surface normal toward the incoming ball by the crater angle
       theta_c = 15.4 deg * (v / 18.6 m/s) * (impact angle / 44.4 deg)   [Penner]
    2. Normal: v_n' = -e v_n with e(v_n) from Penner's fit, scaled per surface.
    3. Tangential: friction opposes contact-point slip, capped at the impulse that
       brings the ball to pure rolling (2/7 of slip for a solid sphere).
    """
    n0 = np.stack([-dhdx, -dhdy, np.ones_like(dhdx)], axis=1)
    n0 /= np.linalg.norm(n0, axis=1, keepdims=True)
    speed = np.linalg.norm(vel, axis=1) + 1e-9
    vn0 = np.sum(vel * n0, axis=1, keepdims=True)
    vt0 = vel - vn0 * n0
    vt0_mag = np.linalg.norm(vt0, axis=1, keepdims=True) + 1e-9
    t_hat = vt0 / vt0_mag
    impact_deg = np.degrees(np.arctan2(-vn0[:, 0], vt0_mag[:, 0]))
    theta_c = np.radians(15.4 * (speed / 18.6) * (impact_deg / 44.4) * CRATER[surf])
    n = np.cos(theta_c)[:, None] * n0 - np.sin(theta_c)[:, None] * t_hat

    vn = np.sum(vel * n, axis=1, keepdims=True)
    vt = vel - vn * n
    a = np.abs(vn[:, 0])
    e = np.where(a <= 20.0, 0.510 - 0.0375 * a + 0.000903 * a ** 2, 0.120)
    e = (e * RESTITUTION[surf])[:, None]
    mu = MU_BOUNCE[surf][:, None]

    slip = vt + np.cross(omega, -ball.radius * n)
    slip_mag = np.linalg.norm(slip, axis=1, keepdims=True) + 1e-9
    roll_frac = 1.0 / (1.0 + 1.0 / ball.inertia_k)       # 2/7 for k = 0.4
    jt = np.minimum(mu * (1 + e) * np.abs(vn), roll_frac * slip_mag)
    dvt = -jt * slip / slip_mag

    new_vel = vt + dvt - e * vn * n
    new_omega = omega + np.cross(-n, dvt) / (ball.inertia_k * ball.radius)
    new_vn = np.sum(new_vel * n0, axis=1)                 # rebound speed off the true surface
    return new_vel, new_omega, new_vn


# ----------------------------------------------------------------------------
# Simulator
# ----------------------------------------------------------------------------
@dataclass
class Result:
    rest: np.ndarray          # (n, 2) final x, y
    status: np.ndarray        # AT_REST / IN_WATER / OUT_OF_BOUNDS
    surface: np.ndarray       # surface code where the ball finished
    first_land: np.ndarray    # (n, 2) first ground contact (carry)
    paths: list               # trajectories (x, y, z arrays) for the first few samples


def simulate(course: Course, v0, w0, start_xy, ball=Ball(), env=Environment(),
             dt=0.1, t_max=40.0, keep_paths=25) -> Result:
    n = len(v0)
    pos = np.zeros((n, 3))
    pos[:, :2] = start_xy
    pos[:, 2] = course.sample(pos[:, 0], pos[:, 1])[0]
    vel = v0.copy()
    omega = w0.copy()

    phase = np.full(n, FLIGHT)
    status = np.full(n, AT_REST)
    first_land = np.full((n, 2), np.nan)
    k = min(keep_paths, n)
    paths = [[pos[i].copy()] for i in range(k)]
    recorded_end = [False] * k

    def deriv(v, w):
        return v, flight_accel(v, w, ball, env), -w / env.spin_decay_tau

    t = 0.0
    while t < t_max and np.any(phase != DONE):
        # ---- Flight: RK4 on airborne balls --------------------------------
        f = np.flatnonzero(phase == FLIGHT)
        if f.size:
            p0, v_0, w_0 = pos[f], vel[f], omega[f]
            k1 = deriv(v_0, w_0)
            k2 = deriv(v_0 + 0.5 * dt * k1[1], w_0 + 0.5 * dt * k1[2])
            k3 = deriv(v_0 + 0.5 * dt * k2[1], w_0 + 0.5 * dt * k2[2])
            k4 = deriv(v_0 + dt * k3[1], w_0 + dt * k3[2])
            p1 = p0 + dt / 6 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0])
            v1 = v_0 + dt / 6 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1])
            w1 = w_0 + dt / 6 * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2])

            h0 = course.sample(p0[:, 0], p0[:, 1])[0]
            h1, _, _, _, inside = course.sample(p1[:, 0], p1[:, 1])
            pos[f], vel[f], omega[f] = p1, v1, w1

            oob = ~inside
            phase[f[oob]] = DONE
            status[f[oob]] = OUT_OF_BOUNDS

            hit = inside & (p1[:, 2] < h1)
            if np.any(hit):
                g = f[hit]
                gap0 = np.maximum(p0[hit, 2] - h0[hit], 0)
                gap1 = p1[hit, 2] - h1[hit]
                frac = (gap0 / (gap0 - gap1 + 1e-12))[:, None]
                pc = p0[hit] + frac * (p1[hit] - p0[hit])
                vc = v_0[hit] + frac * (v1[hit] - v_0[hit])
                h, gx, gy, surf, _ = course.sample(pc[:, 0], pc[:, 1])
                pc[:, 2] = h
                pos[g] = pc

                new = np.isnan(first_land[g, 0])
                first_land[g[new]] = pc[new, :2]

                wet = surf == 4
                phase[g[wet]] = DONE
                status[g[wet]] = IN_WATER

                dry = ~wet
                if np.any(dry):
                    gd = g[dry]
                    nv, nw, vn = bounce(vc[dry], omega[gd], gx[dry], gy[dry], surf[dry], ball)
                    vel[gd], omega[gd] = nv, nw
                    to_roll = vn < ROLL_THRESHOLD
                    phase[gd[to_roll]] = ROLL
                    vel[gd[to_roll], 2] = 0.0

        # ---- Roll: balls on the ground ------------------------------------
        r = np.flatnonzero(phase == ROLL)
        if r.size:
            _, gx, gy, surf, _ = course.sample(pos[r, 0], pos[r, 1])
            grad = np.stack([gx, gy], axis=1)
            v = vel[r, :2] - (5 / 7) * G * grad * dt           # rolling sphere on a slope
            s = np.linalg.norm(v, axis=1)
            s_new = np.maximum(s - ROLL_RESIST[surf] * G * dt, 0.0)
            v *= (s_new / np.maximum(s, 1e-12))[:, None]
            vel[r, :2] = v

            holds = (5 / 7) * np.linalg.norm(grad, axis=1) <= ROLL_RESIST[surf]
            stopped = (s_new < 1e-3) & holds
            phase[r[stopped]] = DONE

            moving = r[~stopped]
            pos[moving, :2] += vel[moving, :2] * dt
            h, _, _, surf2, inside = course.sample(pos[moving, 0], pos[moving, 1])
            pos[moving, 2] = h
            phase[moving[~inside]] = DONE
            status[moving[~inside]] = OUT_OF_BOUNDS
            wet = inside & (surf2 == 4)
            phase[moving[wet]] = DONE
            status[moving[wet]] = IN_WATER

        for i in range(k):
            if phase[i] != DONE or not recorded_end[i]:
                paths[i].append(pos[i].copy())
                recorded_end[i] = phase[i] == DONE
        t += dt

    # Any first_land still NaN (e.g. went OOB in the air) -> use final position.
    miss = np.isnan(first_land[:, 0])
    first_land[miss] = pos[miss, :2]
    surface = course.sample(pos[:, 0], pos[:, 1])[3]
    return Result(pos[:, :2].copy(), status, surface, first_land,
                  [np.array(p) for p in paths])


# ----------------------------------------------------------------------------
# Heatmap and reporting
# ----------------------------------------------------------------------------
def smooth2d(A, sigma_cells=1.5):
    """Separable Gaussian blur (NumPy only) to turn a histogram into a heatmap."""
    rad = int(3 * sigma_cells)
    ker = np.exp(-0.5 * (np.arange(-rad, rad + 1) / sigma_cells) ** 2)
    ker /= ker.sum()
    A = np.apply_along_axis(lambda m: np.convolve(m, ker, mode="same"), 0, A)
    return np.apply_along_axis(lambda m: np.convolve(m, ker, mode="same"), 1, A)


def landing_density(course: Course, res: Result, bin_size=2.0,
                    sigma_cells=1.5, min_fraction=0.05):
    """Return the shared smoothed landing density used by 2D and 3D views."""
    # Water impacts already have valid on-course coordinates. Clamp OOB endpoints
    # to the nearest boundary so the density shows where each shot left play.
    finish_positions = res.rest.copy()
    finish_positions[:, 0] = np.clip(
        finish_positions[:, 0], course.x0, course.x0 + (course.nx - 1) * course.dx
    )
    finish_positions[:, 1] = np.clip(
        finish_positions[:, 1], course.y0, course.y0 + (course.ny - 1) * course.dx
    )
    bins_x = np.arange(course.x0, course.x0 + course.nx * course.dx + 1, bin_size)
    bins_y = np.arange(course.y0, course.y0 + course.ny * course.dx + 1, bin_size)
    density, edges_x, edges_y = np.histogram2d(
        finish_positions[:, 0], finish_positions[:, 1], bins=[bins_x, bins_y]
    )
    sample_count = density.sum()
    density = smooth2d(density, sigma_cells=sigma_cells)
    # Convolution at the course edge otherwise loses kernel mass. Preserve one
    # total unit per physical shot, including water and OOB outcomes.
    if density.sum() > 0:
        density *= sample_count / density.sum()
    threshold = density.max() * min_fraction if density.size else 0.0
    visible = density >= threshold if threshold > 0 else np.zeros_like(density, dtype=bool)
    centers_x = 0.5 * (edges_x[:-1] + edges_x[1:])
    centers_y = 0.5 * (edges_y[:-1] + edges_y[1:])
    return centers_x, centers_y, density, visible


def shot_statistics(res: Result, start_xy, aim_xy) -> dict[str, float]:
    """Return display-ready shot metrics without printing or plotting."""
    start = np.asarray(start_xy)
    aim_dir = np.asarray(aim_xy) - start
    aim_distance = np.linalg.norm(aim_dir)
    if aim_distance == 0:
        raise ValueError("aim point must differ from start point")
    aim_dir = aim_dir / aim_distance
    right = np.array([aim_dir[1], -aim_dir[0]])          # unit vector to the right of aim
    carry = (res.first_land - start) @ aim_dir * M_TO_YD
    total = (res.rest - start) @ aim_dir * M_TO_YD
    lateral = (res.rest - start) @ right * M_TO_YD
    n = len(res.status)
    stats = {
        "carry_mean_yd": float(carry.mean()),
        "carry_sd_yd": float(carry.std()),
        "total_mean_yd": float(total.mean()),
        "total_sd_yd": float(total.std()),
        "lateral_mean_yd": float(lateral.mean()),
        "lateral_sd_yd": float(lateral.std()),
        "water_pct": float(100 * np.mean(res.status == IN_WATER)),
        "ob_pct": float(100 * np.mean(res.status == OUT_OF_BOUNDS)),
    }
    for code, name in enumerate(SURFACES):
        if name != "water":
            stats[f"{name}_pct"] = float(
                100 * np.sum((res.status == AT_REST) & (res.surface == code)) / n
            )
    return stats


def summarize(res: Result, start_xy, aim_xy):
    stats = shot_statistics(res, start_xy, aim_xy)
    print(f"  carry   mean {stats['carry_mean_yd']:6.1f} yd   sd {stats['carry_sd_yd']:5.1f}")
    print(f"  total   mean {stats['total_mean_yd']:6.1f} yd   sd {stats['total_sd_yd']:5.1f}")
    print(
        f"  lateral mean {stats['lateral_mean_yd']:+6.1f} yd   "
        f"sd {stats['lateral_sd_yd']:5.1f}  (+ = right)"
    )
    print("  finish: ", end="")
    parts = []
    for name in SURFACES:
        if name == "water":
            continue
        parts.append(f"{name} {stats[f'{name}_pct']:.1f}%")
    parts.append(f"water {stats['water_pct']:.1f}%")
    parts.append(f"OB {stats['ob_pct']:.1f}%")
    print(", ".join(parts))


def _draw_top_down(ax, course: Course, res: Result, start_xy, aim_xy,
                   actual: Result | None, title: str):
    xs = course.x0 + course.dx * np.arange(course.nx)
    ys = course.y0 + course.dx * np.arange(course.ny)
    # Display: downrange goes up the screen, right is right.
    Xd, Yd = np.meshgrid(-ys * M_TO_YD, xs * M_TO_YD)

    ax.pcolormesh(Xd, Yd, course.S, cmap=ListedColormap(SURFACE_COLORS),
                  vmin=-0.5, vmax=len(SURFACES) - 0.5, shading="nearest")
    ax.contour(Xd, Yd, course.H, levels=12, colors="k", linewidths=0.3, alpha=0.3)

    cx, cy, density, visible = landing_density(course, res)
    masked_density = np.ma.masked_where(~visible, density)
    HX, HY = np.meshgrid(-cy * M_TO_YD, cx * M_TO_YD)
    heat = ListedColormap(plt.get_cmap("inferno")(np.linspace(0.35, 1.0, 256)))
    ax.pcolormesh(HX, HY, masked_density, cmap=heat, alpha=0.8, shading="nearest")

    for p in res.paths:
        ax.plot(-p[:, 1] * M_TO_YD, p[:, 0] * M_TO_YD, lw=0.5, color="white", alpha=0.5)
    sx, sy = start_xy
    ax.plot(
        [-sy * M_TO_YD, -aim_xy[1] * M_TO_YD],
        [sx * M_TO_YD, aim_xy[0] * M_TO_YD],
        color="cyan",
        linestyle="--",
        linewidth=1.4,
        alpha=0.9,
    )
    ax.plot(-sy * M_TO_YD, sx * M_TO_YD, "wo", ms=6, mec="k")
    ax.plot(-aim_xy[1] * M_TO_YD, aim_xy[0] * M_TO_YD, "w+", ms=14, mew=2)
    if actual is not None:
        ax.plot(-actual.rest[0, 1] * M_TO_YD, actual.rest[0, 0] * M_TO_YD,
                "*", color="cyan", ms=16, mec="k", label="actual shot")
        ax.legend(loc="lower left")
    ax.set_aspect("equal")
    ax.set_xlabel("yards (right +)")
    ax.set_ylabel("yards downrange")
    ax.set_title(title)


def _draw_side_view(ax, res: Result):
    for p in res.paths:
        ax.plot(p[:, 0] * M_TO_YD, p[:, 2] * M_TO_YD, lw=0.8, alpha=0.7)
    ax.set_xlabel("yards downrange")
    ax.set_ylabel("height (yd)")
    ax.set_title("Side view of sample trajectories")
    ax.grid(alpha=0.3)


def plot_top_down(course: Course, res: Result, start_xy, aim_xy,
                  actual: Result | None, title: str):
    """Create the primary tactical view without constructing the side view."""
    fig, ax = plt.subplots(figsize=(7, 10))
    _draw_top_down(ax, course, res, start_xy, aim_xy, actual, title)
    fig.tight_layout()
    return fig


def plot_side_view(res: Result):
    """Create an optional trajectory profile figure."""
    fig, ax = plt.subplots(figsize=(11, 4))
    _draw_side_view(ax, res)
    fig.tight_layout()
    return fig


def plot(course: Course, res: Result, start_xy, aim_xy, actual: Result | None,
         title: str, out_path: str | None = None, show: bool = False):
    """Create the original combined CLI report."""
    fig, (ax, ax2) = plt.subplots(1, 2, figsize=(13, 8),
                                  gridspec_kw=dict(width_ratios=[1, 1.4]))
    _draw_top_down(ax, course, res, start_xy, aim_xy, actual, title)
    _draw_side_view(ax2, res)

    fig.tight_layout()
    if out_path:
        fig.savefig(out_path, dpi=130)
        print(f"  saved {out_path}")
    if show:
        plt.show()
    return fig


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--club", default="driver", choices=CLUBS)
    ap.add_argument("--shot", default="stock", choices=SHOT_TYPES)
    ap.add_argument("--n", type=int, default=100, help="number of Monte Carlo samples")
    ap.add_argument("--start", type=float, nargs=2, default=[2.0, 0.0], metavar=("X", "Y"),
                    help="ball position in metres (x downrange, y left)")
    ap.add_argument("--target", type=float, nargs=2, default=[260.0, -5.0], metavar=("X", "Y"),
                    help="aim point in metres (x downrange, y left)")
    ap.add_argument("--wind-mph", type=float, default=0.0)
    ap.add_argument("--wind-dir", type=float, default=0.0,
                    help="direction the wind blows TOWARD, deg; 0 = downwind, 90 = toward the right")
    ap.add_argument("--air-density", type=float, default=1.225)
    ap.add_argument("--seed", type=int, default=2)
    ap.add_argument("--out", default="heatmap.png")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    course = make_test_hole()
    club = CLUBS[args.club]
    wd = np.radians(args.wind_dir)
    env = Environment(air_density=args.air_density,
                      wind=args.wind_mph * MPH * np.array([np.cos(wd), -np.sin(wd), 0.0]))

    start = np.array(args.start)
    aim = np.array(args.target)
    to_aim = aim - start
    aim_deg = np.degrees(np.arctan2(-to_aim[1], to_aim[0]))   # positive = right

    rng = np.random.default_rng(args.seed)

    # Forecast: N samples.
    Z = draw_standard_normals(args.n, rng)
    v0, w0, _ = launch_conditions(Z, club, args.shot, aim_deg)
    t0 = time.perf_counter()
    res = simulate(course, v0, w0, start, env=env)
    elapsed = time.perf_counter() - t0

    # The actual shot: one more draw from the same distribution and code path.
    Za = draw_standard_normals(1, rng)
    va, wa, _ = launch_conditions(Za, club, args.shot, aim_deg)
    actual = simulate(course, va, wa, start, env=env, keep_paths=0)

    print(f"{club.name}, {args.shot}, {args.n} samples: simulated in {elapsed * 1000:.0f} ms")
    summarize(res, start, aim)
    title = f"{club.name} ({args.shot}), {args.n} samples"
    if args.wind_mph:
        title += f", wind {args.wind_mph:.0f} mph @ {args.wind_dir:.0f}°"
    plot(course, res, start, aim, actual, title, args.out, args.show)


if __name__ == "__main__":
    main()
