# Spin During Bounce and the Deferred Skid Phase

This note records the current spin-contact model, what it already supports for
unusual spin builds, and the intentionally deferred skid-phase work. It is not
an implementation specification for that future issue.

## Current impulsive bounce

At impact, the velocity of the ball's contact point relative to the turf is

$$
\mathbf u=\mathbf v_t+\boldsymbol\omega\times(-R\mathbf n).
$$

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
|\Delta v_t|_\mathrm{friction}=\mu(1+e)|v_n|.
$$

The implementation uses the smaller value. The same impulse changes angular
velocity through its torque:

$$
\Delta\boldsymbol\omega=
\frac{(-\mathbf n)\times\Delta\mathbf v_t}{kR}.
$$

Consequently, spin is coupled to bounce rather than being only an aerodynamic
effect. Strong backspin can check or reverse horizontal motion; topspin can
increase forward release; sidespin can create a lateral impulse.

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

## Known limitation: roll begins too early

After bounce, the simulator enters `ROLL` when rebound speed normal to the true
surface is below `ROLL_THRESHOLD`. The roll phase then:

- assumes pure rolling immediately;
- no longer evolves or consults angular velocity;
- applies the rolling-sphere $5/7$ slope acceleration;
- applies translational rolling resistance.

This loses important behavior when a low-bouncing ball still has large
contact-point slip. An extreme-backspin ball should be able to skid, check, or
reverse before rolling. Topspin and sidespin should likewise affect the ground
path during that interval.

## Deferred skid-phase issue

A future `SKID` phase should sit between `FLIGHT` and `ROLL`:

1. Keep the ball constrained to the local terrain.
2. Evolve both linear and angular velocity under surface friction.
3. Resample the terrain normal and surface type as the ball moves.
4. Transition to `ROLL` only when
   $|\mathbf v_t+\boldsymbol\omega\times(-R\mathbf n)|$ is sufficiently small.
5. Handle stopping, water, out-of-bounds, and surface boundaries during skid.
6. Preserve passivity: friction must not increase total kinetic energy.

Additional future physics may include torsional resistance for spin about the
surface normal and finite-time normal/tangential turf compliance. Those are
separate from the minimum viable skid phase.

## Related analysis

See [`crater_model/README.md`](crater_model/README.md) for the effective-plane
geometry and the speed-independent p=0 crater law.

