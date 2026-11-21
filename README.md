# Golf Game

A physics-based golf simulation prototype for a roguelike where items bend the
physics in the player's favor. Shots are distributions rather than timing-based
skill checks: the game samples launch conditions, simulates flight, bounce, and
roll, and reports where the ball is likely to finish.

Project documentation:

- [`AGENTS.md`](AGENTS.md): implementation constraints and handoff context.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): current Streamlit, Godot,
  Terrain3D, and live-worker architecture.
- [`docs/COURSE_AUTHORING.md`](docs/COURSE_AUTHORING.md): complete workflow and
  Terrain3D lifecycle rules for adding another playable hole.
- [`docs/UPGRADES.md`](docs/UPGRADES.md): campaign upgrade catalog, stacking,
  and state ownership.
- [`REACH_GOALS.md`](REACH_GOALS.md): long-term item and synergy ideas.

## Physics lab

The Streamlit app exposes item-like effects and numerical-fidelity controls,
including launch speed and angle, spin, global and directional dispersion,
spin decay, Magnus lift, wind, air density, drag, gravity, integration timestep,
terrain resolution, and sample count.

The app deliberately reuses the same random samples while settings are unchanged,
making visual comparisons stable and reproducible.

### Windows setup

The virtual environment is intentionally not committed. Each developer creates
their own after cloning the repository. From PowerShell in the repository root:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m streamlit run streamlit_app.py
```

If the Python launcher is unavailable but `python` is Python 3.13, create the
environment with:

```powershell
python -m venv .venv
```

After the first setup, launch the app with only:

```powershell
.\.venv\Scripts\python.exe -m streamlit run streamlit_app.py
```

Using the environment's Python directly means PowerShell activation is optional.

## Command-line simulator

The original simulator remains available:

```powershell
python golf_sim.py
python golf_sim.py --club 7iron --start 230 0 --target 385 -5
python golf_sim.py --shot draw --wind-mph 12 --wind-dir 90
```

Run the lightweight tests with:

```powershell
python -m unittest -q
```

## Godot game frontend

The `godot/` directory contains the real-time game frontend prototype. It is
separate from the Streamlit physics lab and uses Terrain3D to render the same
height and surface grids used by the Python physics engine.

Install the standard Godot editor on Windows with:

```powershell
winget install --id GodotEngine.GodotEngine -e
```

The Winget package may not add `godot` to `PATH`. From the repository root,
locate the installed executable once per PowerShell session:

```powershell
$godot = Get-ChildItem `
  "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*" `
  -Filter "Godot_v*-stable_win64.exe" -Recurse |
  Select-Object -First 1 -ExpandProperty FullName
```

Launch the editor with:

```powershell
& $godot --editor --path .\godot
```

Press **F5** to run the configured project. The main menu offers a restricted
**9-Hole Run** foundation and the unrestricted **Physics Sandbox**. Open
`main.tscn` and press **F6** to run that scene directly in Sandbox mode, which
preserves the fast physics-development workflow used throughout this project.

Campaign mode currently establishes the persistent player-state foundation; it
does not yet advance through nine holes or award upgrades. A new run begins
with a 7-iron, Chip from 0-40%, Stock at 100%, and three baseline stats:

- **Power 10**, resolving to normal launch speed;
- **Control 10**, resolving to normal launch dispersion;
- **Spin 10**, resolving to normal launch spin.
- **Mis-hit chance 10%**, used for the independent actual-shot failure roll.

Press **C** or **I**, or click **CHARACTER**, to view stats, their resolved
physics effects, unlocked clubs and shots, and the collected-upgrade inventory.
The campaign hides course switching, ball placement, debug perks, and forced
mis-hit controls. Sandbox retains all of them.

For the current campaign vertical slice, reaching the green presents three
upgrade cards. Choose one to add it permanently to the run and restart the Test
Hole. The pool contains stackable +1 Power, +1 Control, and +1 Spin upgrades;
stackable -1 percentage-point Mis-hit Chance; the four missing clubs; and the
Smooth and Full Power shot unlocks. See
[Campaign Upgrades](docs/UPGRADES.md) for the catalog and ownership boundary.
Each completed Test Hole advances the displayed campaign hole number and is
recorded on the persistent **SCORECARD**, opened with its HUD button or **P**.
During actual-shot playback, a live ticker displays the precalculated ball
speed in mph and spin magnitude in rpm.

In the running game:

- right-drag across the course to turn the aim direction and request a live
  500-shot probability preview; aiming wraps through a full 360 degrees;
- choose a club from the **Club** dropdown;
- use the **shot-power rail** to choose a Chip from 1–40%, Smooth at 80%, Stock
  at 100%, or Full Power at 120%; 0% means no shot, and the 50% marker remains
  locked upgrade space;
- the HUD displays the initial 10% mis-hit chance; actual shots roll this
  separately from the normal launch distribution and announce the selected
  club-specific failure, while the current preview intentionally excludes
  mis-hits;
- open **MIS-HIT DEBUG** to radio-select the normal roll, a guaranteed clean
  shot, or any failure mode valid for the selected club;
- open **PERKS** to toggle the prototype **Power +10%**,
  **Consistency +20%**, and **Spin +50%** perk squares; active perks light up
  and immediately regenerate the preview;
- middle-drag to pan and left-drag to orbit; use the wheel to adjust shot power
  across unlocked values, **Shift+wheel** to zoom toward the world position
  under the cursor, **W/S** or **Up/Down** to select a longer/shorter club, and
  hold **Tab** to temporarily hide the probability fog;
- use the lower-right minimap for a persistent top-down overview, and
  **TACTICAL VIEW** to restore the default spectator angle;
- press **SHOOT** or the **Space bar** to calculate a separate random shot and
  animate it;
- after the ball stops, take the next shot from its new position;
- the current Tee, Fairway, Rough, or Bunker lie modifies speed, launch, spin,
  and dispersion according to the selected club; the preview status reports
  the active lie;
- after a water shot, choose **DROP NEAR WATER (+1)** or **REPLAY SHOT (+1)**;
- an out-of-bounds shot automatically returns to the previous lie and adds one
  penalty stroke;
- follow the separate shot, penalty, and total-score counts at the top left;
- continue until the ball finishes on the green, or press **RESET HOLE** to
  return to the tee.

For physics calibration, **DEBUG PLACE BALL** intersects the next terrain click
with the rendered heightfield, makes it the new lie, and immediately
recalculates the preview. It does not require a Terrain3D collision body.
During an actual shot the
ball and trail are phase-colored: cyan is flight, yellow is skid, green is
clean roll, and gray is stopped.

The collapsible **PERKS** panel is a growing physics sandbox. Its current
toggles are Power +10% initial speed, Consistency -20% across all launch
standard deviations, and Spin +50% launch spin magnitude. Toggle changes are
included in preview cache keys and apply identically to the independent shot.

Chip power is a gameplay action setting rather than an item modifier. The
initial player-facing unlock ends at 40%; the physics model still converges
exactly to Stock at 100% for calibration and future unlocks.
Reducing power lowers mean speed, spin, and launch, while club-specific
`CHIP_PROFILES` retain absolute speed/spin uncertainty and increase angular
dispersion. The wedge has the mildest partial-shot penalty and the driver the
strongest. These coefficients are intentionally easy to retune after play.
See [Variable-Power Chip Shots](docs/CHIP_SHOTS.md) for the equations and
current per-club table.

The discrete rail actions use named launch profiles. Smooth produces 80% mean
speed with 75% of Stock dispersion. Full Power produces 120% mean speed with
135% dispersion. They retain the same deterministic preview cases as the
other rail positions, and their existing lie-specific modifiers still apply.
See [Mis-hit Model](docs/MISHITS.md) for the initial club tables, terminology,
launch transformations, and preview boundary.

The tactical camera automatically fits the highest-density region containing
85% of the preview probability mass. This captures meaningful bounce, skid,
and roll lobes without allowing a handful of extreme samples to zoom the view
out unnecessarily. **TACTICAL VIEW** restores that computed framing after
manual camera movement.

The **OUTCOME CHANCES** HUD uses the same 500-shot preview to report the finish
percentage on fairway, rough, green, bunker, water, and out of bounds. Cached
and newly calculated previews update it through the same payload path.

**FLYOVER** runs a guided drone-like camera pass along the current aim line. It
starts behind and above the ball, follows terrain elevation through the
probability distribution, looks forward and slightly downward, briefly holds
at the end, and returns to the adaptive tactical view. Its default travel speed
is 48 m/s. Press **FLYOVER** again
or **TACTICAL VIEW** to cancel the pass.

The left **Scene** panel contains nodes. Select the root `Main` node to edit
camera, playback, aim-guide, and terrain-grid properties in the right
**Inspector** panel. The subtle 20-yard dashed square grid is draped over the terrain;
its spacing, curve resolution, dash pattern, and surface lift are exposed under
**Terrain Grid**.
Those Inspector sections are properties of `Main`, not additional nodes.

The `.venv` must exist because the Godot prototype starts its persistent
Python physics worker from `.venv\Scripts\python.exe`.

This F6 scene is the current gameplay prototype, not a separate physics-debug
scene. Its perk panel is deliberately a development-friendly loadout selector
for now; later, the same square slots can display acquired item icons.

### Rebuilding the exported course

The following steps are only necessary after changing the semantic
`CourseSpec`, its compiler, or the exported course resolution; they are not
required every time Godot starts. `course_spec.py` is the shared
authoring/procedural boundary; Python physics and Godot terrain are both baked
from it.

Regenerate all registered course interchange files after changing a course:

```powershell
.\.venv\Scripts\python.exe .\export_godot_course.py
```

Then use the included one-shot Godot builder to convert them to Terrain3D's
native region data:

```powershell
& $godot --headless --path .\godot --script res://tools/build_test_hole.gd
```

The F6 prototype currently includes **TEST HOLE** and **WATER CARRY** buttons.
Changing holes switches both the Terrain3D render bake and the Python physics
terrain, then starts a fresh hole from that CourseSpec's tee.

Python physics coordinates and Godot world coordinates are both measured in
meters. The mapping is Python downrange `x` to Godot `-Z`, Python leftward `y`
to Godot `-X`, and height `z` to Godot `+Y`. Player-facing distances should be
converted to yards only at the UI boundary. The live worker returns density
grids for previews and a newly sampled `Result.paths` trajectory for each shot.

### Live physics worker

The Godot prototype starts `physics_worker.py` from the repository `.venv`
and exchanges versioned, newline-delimited JSON over redirected standard IO.
Aim previews use a fixed preview seed and are cached by their complete physics
settings; actual shots use a separate seed and are never selected from preview
samples. `godot/physics_client.gd` owns the process boundary so a future native
physics client can replace Python without changing the renderer or UI.
