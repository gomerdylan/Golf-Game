# Runtime architecture

## Purpose

The prototype has two frontends around one canonical model:

- Streamlit is the physics laboratory for distributions, surfaces, numerical
  fidelity, and experimental item effects.
- Godot is the real-time prototype for aiming, probability communication,
  cameras, shot animation, and the eventual game loop.

Both use `golf_sim.py`. Godot should not grow a separate physics model while the
simulation is changing rapidly.

## Component map

```text
AUTHORING
golf_sim.make_test_hole()
    -> export_godot_course.py
    -> compact arrays
    -> godot/tools/build_test_hole.gd
    -> Terrain3D regions

RUNTIME
Godot controls -> main.gd -> physics_client.gd
    -> JSON line over a child-process pipe
    -> physics_worker.py -> golf_sim.py
    <- density grid or trajectory
    <- main.gd builds fog or animates the ball
```

## Units and coordinates

Physics and Godot use meters. Golf-facing labels may use yards, but terrain,
velocities, and trajectories are never scaled for display units.

| Meaning | Python | Godot |
|---|---:|---:|
| Downrange | `+x` | `-Z` |
| Player's left | `+y` | `-X` |
| Up | `+z` | `+Y` |

A Python point `(x, y, z)` therefore becomes Godot `(-y, z, -x)`.

## Preview phase

A preview request contains physical settings, a preview seed, and sample count:

```json
{
  "protocol_version": 1,
  "type": "preview",
  "request_id": 17,
  "preview_seed": 24681357,
  "sample_count": 500,
  "settings": {
    "aim_deg": 7.5,
    "club": "driver",
    "shot_type": "stock",
    "modifiers": {},
    "environment": {}
  }
}
```

The worker regenerates the same standard-normal table from the preview seed.
All settings transform the same cases. Returning to a setting cannot reroll the
preview, nearby comparisons are less noisy, and future sample counts can use
nested prefixes.

The worker simulates the ensemble and returns a cropped, normalized landing
density, statistics, and a small deterministic subset of completed preview
trajectories. Godot renders those paths as ghost lines and creates a
terrain-following layered fog mesh with vertical wisps. The shader animates
appearance only; probability comes from Python.

### Debouncing and caches

Godot debounces unseen settings while a control moves, so it does not request
every intermediate value. Two caches exist:

- The Godot cache makes revisiting settings visually immediate.
- The worker cache avoids repeating exact simulations in that process.

Responses carry request IDs. If an old request finishes after a newer one,
Godot does not display it but may cache it for a later revisit.

Starting an aim drag preserves the current azimuth while the selection camera
locks behind that line. Subsequent horizontal drag rotates the aim and camera
together so the shot axis stays centered. The guide moves continuously while physics requests use
quarter-degree cache steps. Middle-button panning or right-button orbiting
releases the aim-camera lock.

Wheel zoom preserves the ground-plane point under the cursor by adjusting both
orbit distance and selection focus. Because this is manual camera navigation,
it also releases the behind-ball aim-camera lock.

## Shot phase

Shoot sends a separate request with a gameplay shot seed:

```json
{
  "protocol_version": 1,
  "type": "shoot",
  "request_id": 18,
  "shot_seed": 97531004,
  "settings": { "...": "same physical settings" }
}
```

The worker draws one new launch case and integrates one trajectory. It never
selects a trajectory from the preview ensemble. Reproducible seeds support
saves, replays, tests, and bug reports.

Godot hides the aim guide, uses the follow camera, animates the path, and holds
on the stopped ball before resolving its result. The worker returns both the
final coordinates and the last playable-side boundary crossing. Ordinary lies
commit the final coordinates. Water pauses for either a one-stroke lateral drop
at the crossing or one-stroke replay from the previous lie. Out of bounds adds
one penalty stroke and automatically replays from the previous lie. Godot then
requests a new preview context from the resolved position and restores the
selection camera, fog, and aim guide. A final at-rest surface code of `green`
completes the hole; Reset Hole returns state and score to the tee.
The animation camera derives a local forward direction from the actual opening
trajectory. Its Inspector offset is interpreted as right/up/behind in that
shot-local frame, so reverse and lateral shots are followed from behind rather
than from the course's original tee-side direction.
The selection camera is a constrained spectator orbit centered on the
density-weighted fog position. Player yaw and zoom are preserved across shots;
elevation is clamped above the terrain so the course cannot be flipped. A
bounded ground-plane pan offset lets the player inspect the tee or other parts
of the hole without turning the camera into an unrestricted free-fly camera.
Low spectator elevations are allowed for reading slopes, while terrain-height
sampling keeps the camera above the ground.

`main.gd` also builds a lightweight dashed square grid directly from Terrain3D
height samples. Each line is subdivided and draped over the hills, providing
perspective and slope cues without modifying the Python course or ball physics.

## Worker and replacement boundary

`physics_client.gd` starts one unbuffered Python child and exchanges
newline-delimited JSON through redirected standard IO. Stdout is protocol-only;
diagnostics use stderr. The client exposes ready, preview, shot, and error
signals to the rest of Godot.

This is the replacement seam:

```text
Today: PhysicsClient -> Python child
Later: PhysicsClient -> native C++ library/GDExtension
```

UI and rendering code should depend on response data, not Python process details.

### Lifecycle

Pipe-spawned children can outlive Godot. The client sends `shutdown`, closes
pipes, and kills a worker that remains alive. Python exits on shutdown, stdin
EOF, or a broken output pipe.

If Python gains a persistent multiprocessing pool, the coordinator owns and
closes it. Windows pool creation must remain behind an executable entry point,
never at import time.

## Terrain pipeline

The current course is a Python heightfield plus categorical surface grid.
`export_godot_course.py` writes arrays and metadata; the one-shot Godot builder
converts them to Terrain3D regions at 0.5-meter spacing. Committed regions allow
collaborators to run without rebuilding.

Godot is not yet the course editor. Future procedural generation should produce
one canonical physical/visual course representation rather than divergent
physics and art terrain.

## Probability rendering

The fog is an efficient fake volume:

- a terrain-following mesh interpolates density;
- translucent layers add depth;
- randomized billboards add vertical wisps and hide the source grid;
- a shader adds animated noise and color contrast.

This is cheaper and more controllable than true volumetric fog in the current
Compatibility renderer. Visuals may change freely without changing density.

## Performance direction

The worker currently processes requests sequentially. NumPy vectorizes the
ensemble but does not guarantee use of every CPU core. Before parallelizing,
measure launch generation, integration, density construction, serialization,
pipe transfer, Godot mesh reconstruction, and total control-to-fog latency.

If integration dominates, split preview samples across a persistent process
pool and merge results in the coordinator. Benchmark worker counts and reserve
CPU for Godot. A single actual trajectory is too small for sample parallelism.

The eventual production direction is native C++ with SIMD and task scheduling,
while preserving the current logical request/response interface.

## Current limitations

- The test hole is hard-coded in the worker; Godot now supplies each shot's
  current start position.
- The preview seed is constant instead of derived from saved run/hole/stroke
  state.
- The actual-shot counter is not persisted.
- Aim and club have Godot controls; most modifiers remain in Streamlit or the
  worker schema.
- Transport is JSON rather than compact binary data.
- Course export still contains legacy prerecorded previews unused at runtime.
- Putting, lie-dependent launch effects, tournament-precise drop-zone
  selection, multi-hole progression, inventory, and roguelike run state do not
  yet exist.
