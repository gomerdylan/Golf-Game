# Golf Game

A physics-based golf simulation prototype for a roguelike where items bend the
physics in the player's favor. Shots are distributions rather than timing-based
skill checks: the game samples launch conditions, simulates flight, bounce, and
roll, and reports where the ball is likely to finish.

## Physics lab

The Streamlit app currently exposes two item-like effects:

- **Ball speed multiplier** changes launch speed.
- **Dispersion multiplier** scales all launch-condition standard deviations.

The app deliberately reuses the same random samples while settings are unchanged,
making visual comparisons stable and reproducible.

```powershell
python -m pip install -r requirements.txt
python -m streamlit run streamlit_app.py
```

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
