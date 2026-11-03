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
3D cloud of soft camera-facing wisps. Wisp count, height, opacity, size, and
color are driven by the returned density; probability still comes from Python.

### Debouncing and caches

Godot debounces unseen settings while a control moves, so it does not request
every intermediate value. Two caches exist:

- The Godot cache makes revisiting settings visually immediate.
- The worker cache avoids repeating exact simulations in that process.

Responses carry request IDs. If an old request finishes after a newer one,
Godot does not display it but may cache it for a later revisit.

The collapsible perk panel currently exposes two real modifier settings:
Power uses `speed_multiplier = 1.1`, while Consistency uses
`dispersion_multiplier = 0.9` across all sampled launch-condition sigmas. Perk
state is included in the ordinary settings dictionary, so preview caching and
actual shots require no separate item protocol.

## Lie-dependent launch

The course stores tee as a distinct surface rather than treating it as
fairway. Before every preview and actual shot, `physics_worker.py` samples the
surface at `start_xy_m` and asks `lie_launch_modifier()` for the composed
club-lie and shot-lie effects. `launch_conditions()` then combines, in order:

```text
club baseline × shot type × lie interaction × item modifiers
```

Lie modifiers affect mean speed, aggregate launch sigma, mean launch angle,
mean spin, shot-type mean offsets, and spin-axis dispersion. Rough and
bunker interactions are defined for stock, smooth, full, punch, draw, and
fade, all selectable in Godot. Green falls back
to a clean fairway launch profile if queried; water must be resolved through
penalty relief and cannot be used as a launch lie.

`shot_type_mean_offset_multiplier` scales only the intentional mean
start-direction and spin-axis offsets supplied by draw/fade. It is a pre-launch
condition modifier, distinct from `spin_axis_dispersion_multiplier`, and does
not reshape an integrated trajectory.

Starting an aim drag preserves the current azimuth while the selection camera
locks behind that line. Subsequent horizontal drag rotates the aim and camera
together so the shot axis stays centered. The guide moves continuously while physics requests use
quarter-degree cache steps. Middle-button panning or left-button orbiting
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

Course surface colors originate as the shared sRGB `SURFACE_COLORS` palette in
Python. `build_test_hole.gd` converts those channels to linear color before
writing Terrain3D vertex colors; skipping that conversion makes Godot render
the palette substantially brighter than Streamlit.

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

`course_spec.py` defines the engine-neutral semantic `CourseSpec`: bounds,
terrain parameters, tee/cup, fairway centerlines, greens, bunkers, and water.
The canonical test hole compiles into the current uniform raster-backed
`PhysicsTerrain`; simulation depends on its `sample()` and
`inside_oob_apron()` queries rather than on authoring details.

The compiler feathers shaped green elevation into surrounding terrain rather
than overwriting a hard surface mask. `export_godot_course.py` writes the spec,
arrays, and metadata; the one-shot Godot builder converts the render bake to
Terrain3D regions at 0.5-meter spacing. Committed regions allow collaborators
to run without rebuilding.

Godot is not yet the course editor. A future editor and procedural generator
should both produce `CourseSpec`; physics maps and visual terrain are derived
bakes rather than separately authored versions of the hole.

The archived [terrain representation experiment](TERRAIN_RESOLUTION_EXPERIMENT.md)
records the tiled multiresolution prototype, measurements, why that storage
strategy was not adopted, and the intended separation of physics and art
terrain. CourseSpec itself was retained on main.

## Probability rendering

The fog uses Godot's Forward+ volumetric pipeline:

- Python's horizontal density grid and terrain heights are uploaded as one
  small GPU texture whenever a preview changes;
- a bounded `FogVolume` samples that texture in its froxel grid, applies a
  vertical falloff, and adds smooth animated billowing;
- density controls volumetric opacity and the violet-to-orange color ramp;
- a sparse `MultiMesh` population remains as stylized bubbles within the fog.

During shot playback, presentation-only shader multipliers can reduce the
volume and bubble strength without changing probability. When the simulated
ball reaches rest, the follow camera eases into the elevated tactical view
centered on the preview distribution. One second after rest, both shaders
receive a shared dispersal progress: the volume lifts, breaks up, and
evaporates while the bubbles spiral outward and rise. This reveals the actual
lie before control returns to the player.

This avoids the exposed sheets and polka-dot-only appearance of the earlier
prototypes. It requires the Forward+ renderer; Godot performs integration in a
lower-resolution camera-aligned froxel grid with temporal reprojection rather
than ray marching every probability sample at full screen resolution. Visuals
may change freely without changing the underlying Python density.

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
- Aim, club, shot type, and the first Power/Consistency perks have Godot
  controls; most other modifiers remain in Streamlit or the worker schema.
- Transport is JSON rather than compact binary data.
- Course export still contains legacy prerecorded previews unused at runtime.
- Putting, slope-dependent launch effects, tournament-precise drop-zone
  selection, multimodal flyer/duff outcomes, multi-hole progression, inventory,
  and roguelike run state do not yet exist.
