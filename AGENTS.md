# AGENTS.md

## Project intent

Golf Game is a physics-based golf roguelike. The player chooses an action rather
than timing a swing. Before committing, the game shows a Monte Carlo distribution
of possible physics trajectories; committing produces a new, independently
sampled outcome.

Items should start from recognizable golf physics and bend it in legible,
composable ways. The player fantasy is discovering unusual physical synergies,
not merely collecting linear stat upgrades. Read `REACH_GOALS.md` for the design
space and `docs/ARCHITECTURE.md` for the implemented system.

## Simulation semantics

- Use SI units inside Python and Godot. Convert distances to yards only in
  player-facing UI.
- Python coordinates are `(x downrange, y left, z up)`. Godot coordinates are
  `(-y, z, -x)`: `X right, Y up, -Z forward`.
- Preview samples and the actual shot are separate calculations.
- A preview uses one fixed preview seed for the whole shot-decision context.
  Moving away from settings and returning must not reroll it.
- Reuse the same standard-normal cases across aim, club, and modifier changes
  (common random numbers) so comparisons are stable and fog motion is smooth.
- An actual shot uses a separate gameplay seed and a fresh draw. Never select
  the actual trajectory from the preview ensemble.
- An actual shot can fall outside visible fog because previews are finite and
  low-density areas are visually thresholded.
- `sample_count` remains a protocol parameter and different counts should use
  nested sample prefixes. No sample-count item/debuff is currently implemented.

## Runtime architecture

```text
Godot UI and renderer
    -> godot/physics_client.gd
    -> persistent physics_worker.py child process
    -> golf_sim.py
    <- density grid or one trajectory
```

- `golf_sim.py` is the canonical physics model and course definition.
- `physics_worker.py` handles simulation requests, deterministic preview
  caching, and independently seeded actual shots.
- `godot/physics_client.gd` owns process startup, the JSON-lines protocol,
  polling, and shutdown. Keep this boundary narrow so C++ can replace Python
  without changing the UI or renderer.
- `godot/main.gd` owns prototype UI state, debouncing, the Godot cache, fog
  construction, aim guide, animation, and cameras.
- `godot/probability_fog.gdshader` changes appearance only. It must not invent
  or alter probabilities.
- Terrain3D renders regions under `godot/terrain_data/`; the same Python height
  and surface grids drive physics and terrain export.

The protocol is versioned newline-delimited JSON over redirected stdin/stdout.
Worker stdout is protocol-only; diagnostics use stderr. Every request has an ID.
Godot ignores obsolete responses for display but may cache them for later use.

## Worker lifecycle

Godot pipe-launched processes do not automatically die with Godot. Preserve:

- one persistent worker rather than one Python process per request;
- explicit `shutdown` during normal exit;
- termination on EOF or broken pipe in Python;
- closing pipes and killing an unresponsive worker when Godot exits;
- no orphaned worker or process-pool children.

If adding multiprocessing, keep one coordinator and create a persistent internal
pool. Benchmark worker counts and leave CPU for Godot. Never create a process
pool at import time on Windows.

## Preview requests and caches

The aim slider is continuous. Godot debounces unseen settings so dragging does
not queue dozens of simulations. Previously calculated settings display
immediately from the Godot cache. The worker also caches exact requests.

Cache keys must include everything affecting the preview:

- preview context/seed and sample count;
- aim, club, and shot type;
- item modifiers, environment, and wind;
- course, position, and lie state;
- physics-model version if persisted beyond one process.

Deterministic regeneration is a correctness guarantee; caching is a performance
optimization. Do not expand finite precomputed aim previews across clubs, wind,
and items. That dimensionality does not scale. Live gameplay uses the worker;
legacy preview export files are development artifacts only.

## Terrain and generated data

`make_test_hole()` in `golf_sim.py` is currently authoritative. After changing
it or export resolution, run:

```powershell
.\.venv\Scripts\python.exe .\export_godot_course.py
& $godot --headless --path .\godot --script res://tools/build_test_hole.gd
```

Godot world units stay in meters. Terrain3D currently uses 0.5-meter vertex
spacing. Never scale terrain or trajectories to yards.

Terrain3D creates temporary hot-reload DLLs beginning with `~` or ending in
`.TMP`. They are ignored and must not be committed. Real native libraries under
`godot/addons/terrain_3d/bin/` are required.

## Godot communication

- Nodes are objects in the left Scene tree.
- Properties are controls in the right Inspector for the selected node.
- The root `Main` node exposes playback, camera, and aim-guide properties.
- Player controls live in the running window: aim, club, and Shoot.

Assume documentation readers are new to game engines. Name the panel, node,
property section, and exact action.

## Validation

After Python physics, worker, cache, or protocol changes:

```powershell
.\.venv\Scripts\python.exe -m unittest -q
```

After Godot, GDScript, shader, Terrain3D, or integration changes:

```powershell
& $godot --headless --path .\godot --quit-after 8
```

When lifecycle code changes, verify no `physics_worker.py` process remains after
Godot exits. Use small simulations before scaling performance tests.

## Repository hygiene

- Do not commit `.venv/`, Godot import caches, temporary DLLs, or secrets.
- Preserve user changes in a dirty worktree.
- Keep vendored Terrain3D byte-for-byte unless deliberately upgrading it. Do
  not reformat third-party whitespace.
- Do not commit player-specific paths.
- Update `README.md` for user setup/controls, this file for agent constraints,
  and `docs/ARCHITECTURE.md` for structural changes.

## Near-term direction

- Instrument end-to-end preview latency before parallelizing.
- Add shot type, wind, and item controls through the existing settings dictionary
  rather than new transport paths.
- Keep Python canonical while physics changes rapidly.
- Later replace the hot path with native C++ while preserving the
  `PhysicsClient` request/response contract.
