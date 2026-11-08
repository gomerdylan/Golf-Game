# Spin During Bounce and the Skid Phase

This note records the current spin-contact model and its behavior for unusual
spin builds.

## Current impulsive bounce

After directional restitution, the velocity of the ball's contact point
relative to the effective plane is

$$
\mathbf u=\mathbf v_t+\boldsymbol\omega\times(-R\mathbf n).
$$

Here $\mathbf v_t$ is the already tangentially retained center-of-mass velocity.
This combines translation and spin. Backspin, topspin, and sidespin therefore
change both the direction and magnitude of contact-point slip. Friction applies
a tangential impulse opposite $\mathbf u$.

For a ball with $I=kmR^2$, the translational velocity change required to reach
instantaneous pure rolling is

$$
|\Delta v_t|_\mathrm{roll}=\frac{k}{1+k}|\mathbf u|.
$$

The current default $k=0.4$ gives $k/(1+k)=2/7$. Coulomb friction limits the
available change to

$$
|\Delta v_t|_\mathrm{friction}=\mu(1+r_n)|v_n|.
$$

Here $r_n$ is `NORMAL_RESTITUTION`; tangential restitution is already included
in $\mathbf v_t$. The implementation uses the smaller value. The same impulse changes angular
velocity through its torque:

$$
\Delta\boldsymbol\omega=
\frac{(-\mathbf n)\times\Delta\mathbf v_t}{kR}.
$$

Consequently, spin is coupled to bounce rather than being only an aerodynamic
effect. Strong backspin can check or reverse horizontal motion; topspin can
increase forward release; sidespin can create a lateral impulse.

The Coulomb limit here uses `BOUNCE_FRICTION`. It is intentionally independent
of the sustained-sliding coefficient used after the final bounce.

## Extreme-spin behavior

Once the Coulomb limit is active, more spin increases residual slip but cannot
increase the instantaneous friction impulse. This is intentional: finite
friction cannot bring an arbitrarily fast-spinning ball to rolling during one
impact. The ball can leave with substantial remaining spin, which then affects
Magnus force and subsequent bounces.

The effective crater-plane tilt and contact friction are separate mechanisms.
The crater model changes the effective normal direction. Friction then acts in
that rotated contact frame. Reusing the friction coefficient as a crater-angle
cap would risk counting the same resistance twice.

## Ground-constrained skid

After bounce, the simulator enters `SKID` when rebound speed normal to the true
surface is below `SKID_NORMAL_THRESHOLD`, currently 0.5 m/s. During skid it:

- constrains the ball to the local terrain;
- evolves linear and angular velocity together;
- applies `SKID_FRICTION` opposite contact-point slip;
- caps each friction step at the exact no-slip impulse;
- resamples terrain height, normal, and surface type as the ball moves.

The ball enters `ROLL` only when contact-point slip falls below
`SKID_SLIP_THRESHOLD`, currently 0.05 m/s. The rolling phase then applies the
rolling-sphere $5/7$ slope acceleration and translational rolling resistance.
This allows backspin to check or reverse a ball and topspin to add release
before the pure-rolling approximation takes over.

## Static traction during rolling

Rolling without slipping requires static friction to supply torque on a slope.
For a ball with $I=kmR^2$, the minimum coefficient is

$$
\mu_{s,\mathrm{required}}=\frac{k}{1+k}\tan\alpha,
$$

where $\alpha$ is the local slope angle. If this exceeds the surface's
`STATIC_FRICTION`, no-slip rolling cannot be maintained and the ball returns to
`SKID`. Static friction does not itself slow a cleanly rolling ball; rolling
energy loss remains controlled separately by `ROLL_RESIST`.

During `ROLL`, angular velocity is kept consistent with the current linear
velocity and terrain normal. Spin about the surface normal is preserved because
torsional resistance is not modeled.

## Remaining limitations

- Bounce, skid, and static-friction tables are independently tunable gameplay
  fiducials. Bunker skid friction is intentionally much larger to approximate
  plowing through loose sand, which the simple Coulomb model does not resolve.
- Curvature and normal acceleration are ignored while constrained to terrain.
- There is no torsional resistance for spin about the surface normal.
- Finite-time normal and tangential turf compliance remain omitted.

## Related analysis

See [`crater_model/README.md`](crater_model/README.md) for the effective-plane
geometry and the speed-independent p=0 crater law.

