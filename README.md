# Golf Game

A physics-based golf simulation prototype for a roguelike where items bend the
physics in the player's favor. Shots are distributions rather than timing-based
skill checks: the game samples launch conditions, simulates flight, bounce, and
roll, and reports where the ball is likely to finish.

Project documentation:

- [`AGENTS.md`](AGENTS.md): implementation constraints and handoff context.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): current Streamlit, Godot,
  Terrain3D, and live-worker architecture.
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

Open `main.tscn` if it is not already open. Press **F6** to run that scene or
**F5** to run the configured project. In the running game:

- move the **Aim** slider to request a live 500-shot probability preview;
- choose a club from the **Club** dropdown;
- press **SHOOT** to calculate a separate random shot and animate it;
- wait for the stopped-ball hold to return to the shot-selection camera.

The left **Scene** panel contains nodes. Select the root `Main` node to edit
camera, playback, and aim-guide properties in the right **Inspector** panel.
Those Inspector sections are properties of `Main`, not additional nodes.

The `.venv` must exist because the Godot prototype starts its persistent
Python physics worker from `.venv\Scripts\python.exe`.

### Rebuilding the exported course

The following steps are only necessary after changing `make_test_hole()` or
the exported course resolution; they are not required every time Godot starts.

Regenerate the test-hole interchange files after changing `make_test_hole()`:

```powershell
.\.venv\Scripts\python.exe .\export_godot_course.py
```

Then use the included one-shot Godot builder to convert them to Terrain3D's
native region data:

```powershell
& $godot --headless --path .\godot --script res://tools/build_test_hole.gd
```

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
