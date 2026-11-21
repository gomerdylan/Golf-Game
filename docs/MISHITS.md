# Mis-hit Model

Mis-hits are a second stochastic layer applied only to the independently drawn
actual shot. They are deliberately distinct from ordinary launch dispersion:

1. draw a normal intended launch from the selected club, rail action, lie, and
   perks;
2. roll the flat `mishit_chance` (initially 10% in Godot);
3. on failure, uniformly draw one entry from that club's mis-hit table;
4. transform the intended launch speed, angle, spin, start direction, and/or
   spin axis before trajectory integration.

The preview currently stops after step 1. Its fog, ghost trajectories, and
surface percentages therefore describe successful execution only. A future
UI may switch between the normal preview and a pooled mis-hit preview, but the
two should not be overlaid by default.

## Initial club tables

| Club | Uniform mis-hit outcomes |
|---|---|
| Driver | Sliced, Hooked, Topped, Popped Up — 25% each |
| 3-wood | Sliced, Hooked, Topped, Chunked — 25% each |
| 5-iron | Sliced, Hooked, Chunked, Thinned, Shanked — 20% each |
| 7-iron | Sliced, Hooked, Chunked, Thinned, Shanked — 20% each |
| Pitching wedge | Chunked, Bladed, Shanked, Popped Up — 25% each |

The initial launch transformations are:

| Club | Mis-hit | Weight | Speed | Launch | Spin | Start | Spin axis |
|---|---|---:|---:|---:|---:|---:|---:|
| Driver | Sliced | 25% | 0.94× | unchanged | 1.30× | −4° | +28° |
| Driver | Hooked | 25% | 0.95× | unchanged | 1.20× | +4° | −28° |
| Driver | Topped | 25% | 0.62× | 0.08× | 0.20× | unchanged | unchanged |
| Driver | Popped Up | 25% | 0.55× | 1.65× + 8° | 1.35× | unchanged | unchanged |
| 3-wood | Sliced | 25% | 0.94× | unchanged | 1.30× | −4° | +26° |
| 3-wood | Hooked | 25% | 0.95× | unchanged | 1.20× | +4° | −26° |
| 3-wood | Topped | 25% | 0.62× | 0.10× | 0.20× | unchanged | unchanged |
| 3-wood | Chunked | 25% | 0.48× | 0.85× | 0.55× | unchanged | unchanged |
| 5-iron | Sliced | 20% | 0.95× | unchanged | 1.25× | −3° | +22° |
| 5-iron | Hooked | 20% | 0.96× | unchanged | 1.15× | +3° | −22° |
| 5-iron | Chunked | 20% | 0.48× | 0.85× | 0.55× | unchanged | unchanged |
| 5-iron | Thinned | 20% | 0.90× | 0.28× | 0.40× | unchanged | unchanged |
| 5-iron | Shanked | 20% | 0.72× | 0.75× | 0.65× | +24° | +5° |
| 7-iron | Sliced | 20% | 0.95× | unchanged | 1.25× | −3° | +21° |
| 7-iron | Hooked | 20% | 0.96× | unchanged | 1.15× | +3° | −21° |
| 7-iron | Chunked | 20% | 0.45× | 0.85× | 0.50× | unchanged | unchanged |
| 7-iron | Thinned | 20% | 0.92× | 0.24× | 0.35× | unchanged | unchanged |
| 7-iron | Shanked | 20% | 0.70× | 0.72× | 0.60× | +25° | +5° |
| Pitching wedge | Chunked | 25% | 0.38× | 0.90× | 0.45× | unchanged | unchanged |
| Pitching wedge | Bladed | 25% | 0.95× | 0.16× | 0.28× | unchanged | unchanged |
| Pitching wedge | Shanked | 25% | 0.65× | 0.65× | 0.55× | +27° | +4° |
| Pitching wedge | Popped Up | 25% | 0.42× | 1.55× + 8° | 1.20× | unchanged | unchanged |

These operations apply to the already-sampled intended launch. For example,
`0.16×` launch on a bladed wedge means 16% of that particular shot's sampled
launch angle, not 16% of a hard-coded club constant.

The terms follow ordinary right-handed golf usage:

- **slice/hook:** large right/left curvature, with a corresponding initial
  direction bias;
- **top:** contact above the ball's equator, producing a very low, weak shot;
- **pop-up:** high-face or under-ball contact producing a high, short shot;
- **chunk/fat:** turf contact before the ball, losing substantial speed and
  spin;
- **thin/blade:** contact near the ball's equator, producing a low shot that
  can run much farther than intended;
- **shank:** hosel contact sending the ball sharply right.

The transformations in `MISHIT_TABLES` are fiducial gameplay values. Outcome
selection is intentionally uniform for player readability. Explicit table
weights remain an implementation detail so weighting can be reconsidered
later without changing the protocol; they should not currently differ within
a club.

## Determinism and payload

The actual-shot seed is split into independent launch and mis-hit random
streams. Changing mis-hit chance or table weights therefore does not reroll the
underlying intended launch. A shot response includes:

```json
{
  "mishit": true,
  "mishit_key": "slice",
  "mishit_name": "Sliced"
}
```

Godot displays `Mis-hit: Sliced!` when the response arrives. No announcement is
shown for a normally executed shot.

The collapsible **MIS-HIT DEBUG** panel uses a mutually exclusive radio group.
It offers the normal 10% roll, a guaranteed clean shot, or every failure mode
valid for the selected club. A forced selection sends `forced_mishit` and is
applied only to the actual shot; changing it does not alter the normal preview.
