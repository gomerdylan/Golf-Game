# Adding a Playable Hole

This guide records the complete path from a semantic hole definition to a
selectable, physics-backed hole in the Godot F6 prototype. A hole is not just a
Terrain3D asset: Python physics, worker routing, Godot rendering, UI state, and
preview caching must all agree on the same course identifier.

## Source of truth

`CourseSpec` in `course_spec.py` is the engine-neutral source of truth. It
describes the hole in meters using bounds, terrain parameters, tee and cup,
fairway centerlines, greens, bunkers, and water. Python and Godot receive
separate raster bakes derived from this one specification. Do not independently
redraw the physics and visual versions of a hole.

The built-in examples are `test_hole_spec()` and
`water_carry_hole_spec()`. The latter demonstrates a longer dogleg, a forced
water carry, and a different terrain footprint.

## End-to-end checklist

Use one stable snake-case identifier everywhere, such as `water_carry`.

### 1. Define the CourseSpec

Add a function to `course_spec.py` returning a `CourseSpec`. Keep all internal
coordinates in meters. Feature paint order currently matters:

1. rough is the base surface;
2. fairways are painted;
3. greens are painted and their heights blended;
4. ellipses are painted;
5. rectangles are painted last.

Consequently, a water rectangle can overwrite a fairway to create a forced
carry. Check that every feature is inside the declared bounds.

### 2. Expose a physics constructor

Add a constructor in `golf_sim.py`, following `make_test_hole()` and
`make_water_carry_hole()`. It should compile the matching spec at the requested
spacing rather than recreate any geometry.

### 3. Register the worker terrain

Add the identifier and constructor to `COURSES` in `physics_worker.py`. Godot
sends `course_id` with every preview and actual-shot request. `_settings()`
selects the corresponding terrain before sampling the lie or simulating.

`course_id` is part of the settings dictionary and therefore the preview cache
key. Without it, two holes could return the same cached fog for identical aim
and club settings.

### 4. Register the exporter and builder

Add the spec to the loop in `export_godot_course.py`, and add its identifier to
`COURSE_IDS` in `godot/tools/build_test_hole.gd`. Despite its historical name,
the builder processes every registered course.

Close Godot before rebuilding. On Windows, an open editor can lock Terrain3D's
native DLL or temporary hot-reload copy and cause misleading copy/load errors.

```powershell
.\.venv\Scripts\python.exe .\export_godot_course.py
& $godot --headless --path .\godot --script res://tools/build_test_hole.gd
```

This creates two committed asset groups:

```text
godot/course_data/<course_id>/     # spec, compact grids, metadata
godot/terrain_data/<course_id>/    # native Terrain3D regions
```

Commit both so collaborators can play without rebuilding. Legacy trajectory
and fog exports are not authoritative at runtime; the persistent worker
generates live previews and shots.

### 5. Register Godot gameplay state

Add an entry to `COURSE_CONFIGS` in `godot/main.gd`. It currently contains the
display name, tee, physics bounds, and displayed length. Bounds drive the
draped 20-yard contour grid, so stale bounds leave part of a hole ungridded.

Add the Terrain3D node to `godot/main.tscn` with its own `data_directory`, then
add/connect its selection button. `_physics_settings()` must keep sending
`current_course_id`.

Switching holes resets score and ball position, clears preview caches, rebuilds
the contour grid, and requests a preview. Rendered terrain and Python
`course_id` must change as one operation.

## Terrain3D lifecycle warning

Terrain3D 1.1.2 does not behave like an ordinary hideable mesh here. Two failed
approaches established important constraints:

- `visible = false` did not reliably hide internally managed render meshes.
  Both courses appeared, with the larger Water Carry terrain covering Test Hole.
- Assigning `Terrain3D.data_directory` at runtime crashed the native Windows
  extension with `CrashHandlerException`/signal 8.

The current solution preloads separate Terrain3D nodes but keeps only the
selected one in the scene tree. The initially inactive Water Carry node is
removed in `Main._enter_tree()`, before its own enter-tree initialization.
Removing it in `_ready()` is too late: its native renderer has already been
created and can remain visible.

When switching, `main.gd` detaches the active Terrain3D and attaches the
already-configured target. It never mutates `data_directory`. Preserve this
lifecycle unless a future Terrain3D upgrade is explicitly tested.

For more holes, generalize the current two references into a dictionary of
detached Terrain3D nodes while preserving this invariant:

> Only the selected course's Terrain3D node may enter the scene tree.

## Validation

Run:

```powershell
.\.venv\Scripts\python.exe -m unittest -q
```

Then fully restart Godot and exercise this F6 sequence:

1. Confirm Test Hole is the initial terrain and its fog matches it.
2. Switch to the new hole; terrain, grid, label, and fog must change together.
3. Take a shot and confirm collision/lie results match visible surfaces.
4. Switch back and confirm both Test Hole terrain and fog return.
5. Press the active hole button and confirm it resets the hole.
6. Exit and confirm no `physics_worker.py` process remains.

Fog is a useful diagnostic: correct fog over the wrong terrain usually means
Godot and Python disagree about `course_id`, or two Terrain3D renderers became
active simultaneously.

## Current direction

CourseSpec is code-authored, not yet a visual editor. A future Godot editor tool
or procedural generator should produce CourseSpec-compatible data while physics
and visual terrain remain derived bakes. Both grids currently use uniform
0.5-meter spacing. The abandoned multiresolution storage prototype is recorded
in `TERRAIN_RESOLUTION_EXPERIMENT.md` and does not alter this workflow.
