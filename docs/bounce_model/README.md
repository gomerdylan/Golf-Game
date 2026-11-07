# Bounce and restitution model

The bounce combines three mechanisms:

1. rotate the terrain normal using the effective deformation plane;
2. apply normal restitution in that rotated frame;
3. apply a spin-dependent Coulomb friction impulse tangent to that frame.

The result is then returned to flight or moved to the simplified rolling phase.
See [`../crater_model/README.md`](../crater_model/README.md) for the effective
plane derivation and [`../SPIN_BOUNCE_AND_SKID.md`](../SPIN_BOUNCE_AND_SKID.md)
for spin coupling and the deferred skid phase.

## Normal restitution

The normal bounce currently uses Penner's empirical turf fit. For effective
normal impact speed $a=|v_n|$,

$$
e_0(a)=
\begin{cases}
0.510-0.0375a+0.000903a^2, & a\leq20\ \mathrm{m/s},\\
0.120, & a>20\ \mathrm{m/s}.
\end{cases}
$$

The final coefficient is

$$
e=e_0 M_{v,s},
$$

where `RESTITUTION_VELOCITY_MULTIPLIER` explicitly multiplies rebound velocity,
not energy. The corresponding surface multiplier on normal rebound energy and
bounce height is $M_{v,s}^2$.

Current fiducial values are:

| Surface | Velocity multiplier | Energy/height multiplier |
|---|---:|---:|
| Rough | 0.45 | 0.2025 |
| Fairway | 0.70 | 0.4900 |
| Green | 0.80 | 0.6400 |
| Bunker | 0.15 | 0.0225 |
| Water | 0.00 | 0.0000 |
| Tee | 0.70 | 0.4900 |

These are gameplay-motivated starting points rather than fitted material
measurements. The green is the liveliest maintained surface; fairway and tee
are moderate; rough is strongly damped by vegetation; loose bunker sand is
nearly dead.

![Restitution versus normal impact speed](restitution_vs_normal_speed.png)

The quadratic is an empirical fit over ordinary golf-turf conditions, not a
constitutive law for arbitrary speed. The implementation freezes it at 0.120
above 20 m/s rather than allowing the upward-opening quadratic to increase
without bound. This avoids the most obvious extrapolation failure but still
assumes a constant base 12% velocity restitution at every extreme speed before
the surface multiplier is applied.

At extreme, non-golf speeds, penetration, turf excavation, soil and ball
damage, changing contact area, and rate-dependent material response invalidate
the effective-plane instantaneous-bounce model. A future high-energy regime
should transition to a penetration/failure model or at least make restitution
decay toward zero rather than treating the 0.120 plateau as established data.

## Why shallow skips persisted

The restitution fit becomes proportionally livelier as normal impact speed
falls: $e_0\to0.51$ as $|v_n|\to0$. That contributes to repeated low hops, but
it was not the only issue.

The first speed-independent deformation model used

$$
\theta_c\propto\sin(2\phi).
$$

Near grazing incidence, let $\epsilon=|v_n|/v_t$. Then both the incoming angle
and the effective-plane tilt were proportional to $\epsilon$. The plane angle
approached zero but remained a finite fraction of the incidence angle, allowing
horizontal velocity to be repeatedly redirected upward. Rough and bunker were
especially affected because their `DEFORMATION_ASYMMETRY` values are larger.

The accepted model instead uses

$$
\tan\theta_c=\tan(15.4^\circ)C_s
\frac{\sin^2(2\phi)}{\sin^2(2\times44.4^\circ)}.
$$

This vanishes quadratically at both vertical and grazing incidence. The
effective ramp therefore becomes negligible relative to the incoming angle at
both boundaries. It retains the strongest deformation effect around 45 degrees
and preserves Haake's calibration point.

Regression tests cover both asymptotic limits, speed independence, the angular
peak, and non-reversal of steep spin-free impacts on flat fairway and rough.

## Remaining limitations

- The low-speed restitution rise can still produce several small hops.
- The 0.120 high-speed plateau is an extrapolation policy, not meteor-scale
  material physics.
- The instantaneous model omits finite normal and tangential turf compliance.
- Low rebounds transition directly to pure rolling even if contact-point slip
  remains; a separate skid phase is deferred.
- Surface restitution and deformation-asymmetry values remain fiducial gameplay
  parameters rather than independent material measurements.

Regenerate the plot from the repository root:

```powershell
.\.venv\Scripts\python.exe .\docs\bounce_model\plot_restitution.py
```

## Sources

- A. R. Penner, *The run of a golf ball* (2002):
  <https://www.raypenner.com/golf-run.pdf>
- S. J. Haake, *Apparatus and test methods for measuring the impact of golf
  balls on turf and their application in the field* (1989):
  <https://archive.lib.msu.edu/tic/thesdiss/haake1989a.pdf>
- R. Cross, *Oblique impact of a hard ball on a soft surface* (2021):
  <https://doi.org/10.1088/1361-6404/ac221e>
- S. W. Biber et al., *Measurements and linearized models for golf ball bounce
  on a green* (2023): <https://arxiv.org/abs/2302.02758>
- S. W. Biber, A. R. Champneys, and R. Szalai, *Analysis of point-contact
  models of the bounce of a hard spinning ball on a compliant frictional
  surface* (2022): <https://arxiv.org/abs/2208.11685>

