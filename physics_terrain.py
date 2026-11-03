"""Physics-facing terrain interface.

Simulation code depends on point queries, not on a particular storage layout.
Uniform rasters, tiled multiresolution rasters, or adaptive meshes can therefore
be introduced behind this boundary without changing flight/bounce/roll code.
"""

from __future__ import annotations

from typing import Protocol


class PhysicsTerrain(Protocol):
    def sample(self, x, y):
        """Return height, x/y gradients, surface code, and in-bounds mask."""
        ...

    def inside_oob_apron(self, x, y):
        """Return whether positions remain in the extended simulation area."""
        ...
