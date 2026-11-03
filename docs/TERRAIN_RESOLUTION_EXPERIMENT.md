# Terrain representation experiment

## Status

The full experiment is archived on the branch
`change-resolution-for-different-surfaces` beginning at commit `eed28af`.
The semantic `CourseSpec`, uniform raster compiler, smooth green blending, and
`PhysicsTerrain` query boundary were subsequently adopted on `main`. Only the
tiled multiresolution storage experiment remains branch-only.

The experiment was useful, but its first multiresolution implementation traded
too much simulation speed and surface-classification accuracy for its memory
savings. We intentionally returned to the uniform terrain representation while
preserving the findings here for a future terrain redesign.

## Why we ran it

The prototype used one regular raster for three related jobs:

- physical height and slope queries in Python;
- categorical lie and hazard classification in Python;
- the height and surface-color data baked into Godot Terrain3D.

At 0.5-meter spacing, the test hole contains an `841 x 241` height grid and a
matching surface grid. This is small for the current hole, but uniform grids
scale with area divided by spacing squared. Very long superhuman holes or wide
courses could therefore spend substantial memory on flat or unused areas.

The motivating observation was that a large tilted plane does not need millions
of samples. Its height can be represented exactly by a few parameters or two
triangles. Detail is valuable around rolling greens, bunker lips, shorelines,
and other regions with meaningful curvature or semantic boundaries.

## CourseSpec experiment

The branch introduced an engine-neutral `CourseSpec` containing semantic course
features rather than treating the final raster as the authored hole:

- course bounds;
- base terrain parameters;
- tee and cup locations;
- fairway centerlines and widths;
- greens;
- elliptical bunkers;
- rectangular hazards.

The current test hole was compiled from that specification. The exporter also
wrote the semantic specification alongside the Godot interchange data.

This exposed and fixed a separate green-geometry bug. The old generator replaced
height values only inside the hard green ellipse, creating a real discontinuity
at its edge. The experimental compiler blended the shaped green into surrounding
terrain over an eight-meter transition instead.

`CourseSpec` remains the intended architectural direction and is now active on
`main`. A future human editor and a future procedural generator should produce
the same neutral course definition.

## PhysicsTerrain boundary

The branch introduced a small `PhysicsTerrain` interface centered on two
queries:

```text
sample(x, y)
    -> height, height gradients, surface code, in-bounds flag

inside_oob_apron(x, y)
    -> extended simulation-boundary flag
```

Flight, bounce, roll, previews, and actual shots need terrain queries; they do
not inherently need to know whether terrain is stored as one raster, many tiles,
an adaptive mesh, or an analytic surface. That remains a useful seam for future
work and for an eventual native physics implementation.

## Multiresolution implementation

The experimental `TiledPhysicsTerrain` used:

- a 2-meter base raster over the whole course;
- a 0.5-meter fairway detail tile;
- 0.25-meter tiles around the tee, green, bunkers, and water;
- a coarse spatial lookup table mapping positions to candidate detail tiles;
- vectorized NumPy sampling within each selected raster.

Godot rendering remained an independent 0.5-meter bake. The live worker was
never switched to the experimental terrain.

## Measured results

The comparison used the current test hole and a 500-shot stock-driver ensemble.

| Metric | Uniform 0.5 m | Experimental multiresolution |
|---|---:|---:|
| Core terrain memory | 1,824,129 bytes | 1,148,096 bytes |
| Memory reduction | - | 37.1% |
| Full simulation runtime | 1.0x | approximately 1.6x |
| Final-surface agreement | 100% reference | 97.8% |
| Mean resting-position difference | - | 0.35 m |
| 95th-percentile resting-position difference | - | 0.17 m |

The mean exceeding the 95th percentile indicates a small number of large
outliers. Those are consistent with trajectories diverging after a different
bounce or surface classification near a boundary.

The first naïve tile router was approximately 2.25 times slower than the uniform
grid. Adding the spatial lookup and fast paths improved it to approximately 1.6
times slower, but that was still not acceptable for a preview engine whose main
cost is already hundreds of trajectory integrations.

One incidental improvement was worthwhile: categorical surface values need only
eight bits. Changing the Python surface raster from platform integers to `uint8`
reduced the core uniform terrain arrays from about 3.24 MB to 1.82 MB without
changing their resolution.

## Why we stopped

The experiment coupled two things that want different representations:

1. Height and slope are continuous and tolerate controlled approximation.
2. Surface identity is semantic and must remain precise at fairway, green,
   bunker, water, and out-of-bounds boundaries.

A coarse heightfield can be perfectly adequate on a gentle hill, while a coarse
surface mask can move a hazard boundary enough to change a shot outcome. Detail
tiles also introduced routing and grouping overhead into the hottest repeated
terrain query.

For the current hole, the uniform raster is small, fast, simple, and more
accurate. Prematurely replacing it would optimize the wrong bottleneck.

## Better future options

### Separate height from semantic surfaces

Use a coarse or adaptive representation for height while classifying lies and
hazards from exact vector geometry, signed-distance fields, or a separate compact
high-resolution mask. This is the strongest next direction.

### Sparse course corridor

Do not allocate one enormous rectangle around a winding hole. Divide the course
into fixed regions and store only regions near playable routing, hazards, and
intentional out-of-bounds display space.

### Analytic or adaptive height patches

Flat and tilted areas can use planes. Curved areas can use recursively subdivided
patches, a quadtree, or an adaptive triangle network. A compiler can either:

- generate a high-resolution source and simplify it offline; or
- recursively sample a terrain function and subdivide only when interpolation
  error exceeds a tolerance.

### Preserve vectorization

Any Python implementation must be benchmarked against the simple uniform lookup.
Potential approaches include grouping trajectories by fixed region, compiling
region-local kernels, or moving terrain queries and integration together into
native code. A memory optimization that materially slows every integration step
is not a win.

### Load only the active hole

Runtime memory and installed game size are different problems. Only the current
hole needs to reside in memory. Procedural holes may be stored as compact seeds
and semantic specifications, generated on demand, cached if useful, and evicted.

## Intended visual/art surface

The rendered terrain should not be forced to expose the physics storage layout.
The intended architecture is:

```text
semantic course definition
        |-- physics terrain/query representation
        `-- visual terrain and art meshes
```

Godot may render a higher-resolution Terrain3D surface, an adaptive triangle
mesh, or a deliberately coarse low-poly mesh while Python uses a smooth hidden
physical surface. Both derive from the same semantic course definition, so tee,
green, hazards, and elevations remain aligned.

For the possible vaporwave/N64 direction, a visual-only terrain layer could use:

- stable, decimated triangles rather than exposing Terrain3D's changing LOD
  triangles directly;
- flat or lightly interpolated vertex colors;
- emissive triangle edges;
- the existing square yardage grid as a separate overlay;
- large triangles in simple terrain and locally refined triangles around
  silhouettes and hazards.

Using a coarse visual mesh does not require coarse collision normals. Keeping a
smoother hidden physics surface avoids abrupt rolling and bounce changes at
triangle edges while allowing the rendered course to have an intentional
faceted style.

## Recommended restart point

When terrain scale becomes a demonstrated problem, restart from these steps:

1. Evolve the current `CourseSpec` into a durable, editor-friendly format.
2. Build at least several qualitatively different holes with it.
3. Benchmark realistic maximum course dimensions and active-hole memory.
4. Separate semantic surface classification from height interpolation.
5. Prototype sparse fixed regions before a fully general quadtree.
6. Benchmark preview latency, boundary agreement, and trajectory divergence.
7. Develop the visual triangle/wireframe surface on a separate art branch after
   the semantic and physical course pipeline is stable.

The experiment demonstrated that adaptive terrain is feasible and can save
memory. It also demonstrated that the simplest tiled version is not currently a
net improvement for this game's Python physics hot path.
