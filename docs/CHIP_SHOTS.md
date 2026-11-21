# Variable-Power Chip Shots

Godot presents these actions on one shot-power rail from 0% through 120%:

- **0–30%** is the unlocked continuous Chip zone;
- **80%** is the Smooth notch with better control;
- **100%** is the isolated Stock notch;
- **120%** is the Full Power notch with worse control;
- **50%** remains a locked placeholder for a possible Pitch action;
- **0%** is a no-shot state and disables preview and shooting.

Dragging through a locked span snaps to its nearest unlocked boundary. The
rail can gain further continuous zones or isolated notches—such as the 50%
Pitch placeholder or a wider Chip zone—without replacing the input model or
adding another dropdown.

Chip power is an action setting, not an item modifier. It is included in the
worker request and preview cache key, so moving the slider transforms the same
standard-normal cases instead of rerolling the preview. At power 1.0 every Chip
term converges exactly to Stock.

The backend accepts Chip power through 1.0 for tests and future content, even
though its continuous UI zone stops at 0.30. Smooth and Full are named discrete
profiles: Smooth uses 0.80 mean speed and 0.75 dispersion; Full uses 1.20 mean
speed and 1.35 dispersion. Legacy draw, fade, and punch remain available in
the Python physics lab but are not selectable in the current Godot game UI.

Fog smoothing and its decorative bubbles adapt to the resulting endpoint
footprint rather than directly to the selected power. Compact clouds use a
tighter probability kernel; bubble size and presentation scale smoothly
between the exported `bubble_fade_in_span_m` and
`bubble_full_effect_span_m` thresholds. Bubble population is normalized by
physical grid-cell area so adaptive resolution does not create more particles
per square meter. A deliberately visible minimum billboard population
preserves small clouds at distances where volumetric-fog froxels can miss
them, while individual billboard dimensions are capped to a fraction of the
cloud footprint. Compact volumes also receive a capped density boost to offset
their shorter optical path length. This keeps the fog statistically meaningful
while allowing future perks, lies, and unusual physics to control the
presentation through their actual outcome spread.

## Tunable model

For Chip power $p$, each club has a `ChipProfile` with:

- $K$: `dispersion_penalty`;
- $f_v$: `speed_sigma_floor`;
- $f_\omega$: `spin_sigma_floor`;
- $\Delta\theta$: `launch_reduction_deg`;
- $q$: `spin_power_exponent`.

The partial-shot angular-dispersion multiplier is

$$
D(p)=1+K(1-p)^2.
$$

Mean speed scales directly with power:

$$
\bar v(p)=p\bar v_{stock}.
$$

Speed noise does not shrink directly with the mean. Relative to the stock
absolute speed sigma, its scale is

$$
\frac{\sigma_v(p)}{\sigma_{v,stock}}
=D(p)\left[p+f_v(1-p)\right].
$$

Mean launch and mean spin are

$$
\bar\theta(p)=\bar\theta_{stock}-\Delta\theta(1-p),
\qquad
\bar\omega(p)=p^q\bar\omega_{stock}.
$$

Spin noise uses the analogous floor

$$
\frac{\sigma_\omega(p)}{\sigma_{\omega,stock}}
=D(p)\left[p+f_\omega(1-p)\right].
$$

Launch-angle, start-direction, and spin-axis sigmas receive $D(p)$ in addition
to the ordinary lie, item, and shot dispersion modifiers. This is intentionally
a gameplay model: physical absolute uncertainty may fall with swing strength,
but the sigma floors and club-specific penalty make a long club meaningfully
risky when substituted for a short club.

## Initial coefficients

| Club | $K$ | $f_v$ | $f_\omega$ | $\Delta\theta$ | $q$ |
|---|---:|---:|---:|---:|---:|
| Driver | 3.00 | 0.65 | 0.50 | 2.0° | 1.10 |
| 3-wood | 2.25 | 0.55 | 0.45 | 3.0° | 1.10 |
| 5-iron | 1.40 | 0.45 | 0.35 | 4.0° | 1.05 |
| 7-iron | 0.90 | 0.35 | 0.30 | 5.0° | 1.05 |
| Pitching wedge | 0.40 | 0.25 | 0.20 | 8.0° | 1.00 |

These values are fiducial sandbox settings, not final balance. They live in one
table specifically so playtesting can independently answer:

- should absolute speed sigma fall at low power;
- how severe should the long-club penalty be;
- how quickly should spin disappear;
- whether a lower chip launch produces useful bump-and-run alternatives;
- whether the wedge remains valuable across the short-distance envelope.

## Regression requirements

- Chip at power 1.0 must exactly equal Stock for paired samples.
- Only Chip may use power below 1.0; Stock remains exactly 1.0.
- Physics Chip power must be greater than 0 and at most 1.0; the current UI
  submits values from 0.01 through 0.30.
- Godot must not submit the 0% no-shot state to Python.
- A driver penalty must grow faster than a wedge penalty as power falls.
- Absolute speed sigma must not automatically scale in direct proportion to
  power.

