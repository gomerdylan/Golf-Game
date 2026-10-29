# Golf Game

A physics-based golf simulation prototype for a roguelike where items bend the
physics in the player's favor. Shots are distributions rather than timing-based
skill checks: the game samples launch conditions, simulates flight, bounce, and
roll, and reports where the ball is likely to finish.

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
