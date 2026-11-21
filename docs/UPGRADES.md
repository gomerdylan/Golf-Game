# Campaign Upgrades

## Current prototype loop

Campaign mode currently repeats the fixed Test Hole to exercise the roguelike
reward loop before nine-hole progression is implemented:

1. Play until the ball finishes on the green.
2. Choose one of three eligible upgrades.
3. Apply it to persistent `RunState`.
4. Restart the Test Hole with the new stats and unlocks.

The actual nine-hole course sequence and final results screen are later
milestones. Sandbox completion remains unchanged and does not award upgrades.

## Data model

`upgrade_definition.gd` describes one upgrade type:

- stable ID;
- player-facing title and description;
- effect type, key, and amount;
- maximum number of collectible stacks.

`RunState` owns the catalog, acquired stack counts, persistent character state,
eligibility filtering, random draft generation, and effect application. The UI
only presents definitions and reports the selected definition back to
`RunState`; it does not directly modify physics.

The worker remains inventory-agnostic. Stats and upgrades resolve into ordinary
physics settings in Godot before a preview or actual shot is requested.

## Initial pool

| Upgrade | Maximum copies | Effect |
|---|---:|---|
| +1 Power | 5 | +10% launch speed per point |
| +1 Control | 5 | -10% launch dispersion per point |
| +1 Spin | 5 | +20% launch spin per point |
| -1% Mis-hit Chance | 5 | -1 percentage point per copy |
| Pitching Wedge | 1 | Unlock club |
| 5-iron | 1 | Unlock club |
| 3-wood | 1 | Unlock club |
| Driver | 1 | Unlock club |
| Smooth Shot | 1 | Unlock controlled 80% shot |
| Full Power Shot | 1 | Unlock less-controlled 120% shot |

Three different eligible definitions are drawn for each reward. Stackable
definitions can return on later holes until their cap is reached. A one-time
unlock leaves the pool after collection.

The stack limits and conversion coefficients are prototype tuning values, not
promises about final balance. Future percentage-based upgrades should remain a
separate modifier layer so `+1 Power` and `+10% Power` have unambiguous and
different meanings.
