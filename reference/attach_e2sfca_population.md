# Per-year half of the raster grid: attach population and rasterize demand.

Per-year half of the raster grid: attach population and rasterize
demand.

## Usage

``` r
attach_e2sfca_population(
  grid_geom,
  pop_vals,
  pop_col = "female_pop",
  pop_val_col = pop_col,
  alloc = c("area", "center"),
  conservation_tol = 1e-06,
  na_pop_policy = c("error", "zero")
)
```

## Arguments

- grid_geom:

  Output of \[build_e2sfca_grid_geometry\] (cached per vintage).

- pop_vals:

  data.frame/tibble with \`GEOID\` and a population column.

- pop_col:

  Name to record as the grid's population column.

- pop_val_col:

  Name of the population column in \`pop_vals\` (default = \`pop_col\`).

- alloc:

  Allocation method: \`"area"\` (default; mass-conserving area-weighted
  via \[allocate_pop_areaweighted\]) or \`"center"\` (legacy
  center-based rasterization, retained only for the vintage-seam
  sensitivity comparison — NOT mass-conserving).

- conservation_tol:

  Passed to \[allocate_pop_areaweighted\] (area mode).

- na_pop_policy:

  What to do when a grid tract has no row in \`pop_vals\`, or has an
  \`NA\` population. \`"error"\` (default) fails closed and names the
  offending GEOIDs; \`"zero"\` restores the historical zero-fill as an
  explicit, documented imputation.

## Value

list(pop_rast, tracts, template, pop_col, resolution, area_crs, alloc).

## See also

\[build_e2sfca_grid_geometry\], \[allocate_pop_areaweighted\]

Other E2SFCA raster grid:
[`allocate_pop_areaweighted()`](https://mufflyt.github.io/twostep/reference/allocate_pop_areaweighted.md),
[`build_e2sfca_grid_geometry()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_grid_geometry.md),
[`build_e2sfca_raster_grid()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_raster_grid.md),
[`prepare_e2sfca_iso()`](https://mufflyt.github.io/twostep/reference/prepare_e2sfca_iso.md)
