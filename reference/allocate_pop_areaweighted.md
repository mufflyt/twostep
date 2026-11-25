# Mass-conserving tract-to-grid population allocation (area-weighted).

Center-based rasterization (assign a cell to whichever tract covers its
centre) DROPS the population of any tract too small to contain a cell
centre, and more generally does not conserve each tract's population
locally. At a 500 m CONUS grid this silently lost ~1% of ACS female
population and made the represented national total \*vintage-dependent\*
(2010 vs 2020 tract sets lose different amounts), which confounds the
seam test: an apparent access shift can be a pure change in total demand
rather than spatial redistribution.

## Usage

``` r
allocate_pop_areaweighted(template, tracts, pop, conservation_tol = 1e-06)
```

## Arguments

- template:

  terra SpatRaster defining the target grid (values ignored).

- tracts:

  \`sf\` polygons in the template CRS (equal-area).

- pop:

  numeric vector, \`length == nrow(tracts)\`, per-tract population.

- conservation_tol:

  Max allowed relative per-tract allocation error before this function
  \`stop()\`s (default 1e-6).

## Value

terra SpatRaster of per-cell population \`p_c\` (background 0).

## Details

This allocator instead splits each tract's population across every
template cell it intersects, weighted by intersection area: \$\$w\_{ic}
= A\_{ic} / \sum_h A\_{ih}, \quad p\_{ic} = P_i w\_{ic}, \quad p_c =
\sum_i p\_{ic}\$\$ where \\A\_{ic}\\ is the area of overlap between
tract \\i\\ and cell \\c\\ (from
\`exactextractr::exact_extract(coverage_area = TRUE)\`, planar in the
equal-area CRS). Guarantees, verified numerically here:

- \\\sum_c p\_{ic} = P_i\\ for every tract (per-tract conservation);

- \\\sum_c p_c = \sum_i P_i\\ (global conservation);

- sub-cell tracts and slivers keep ALL their population;

- a tract with zero valid overlap FAILS LOUDLY rather than dropping pop.

## References

Apparicio et al. (2017) doi:10.1186/s12942-017-0105-9 \[source 7\]
documents the population-AGGREGATION error that centroid assignment
incurs in potential-access measures; this area-weighted, mass-conserving
allocation is the remedy the manuscript adopts (recovers the ~1.06% of
the female population that centroid allocation drops). Frozen facts
(allocator sha256, 500 m EPSG:5070, conservation tolerance) are in
docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md.

## See also

\[build_e2sfca_grid_geometry\], \[attach_e2sfca_population\]

Other E2SFCA raster grid:
[`attach_e2sfca_population()`](https://mufflyt.github.io/twostep/reference/attach_e2sfca_population.md),
[`build_e2sfca_grid_geometry()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_grid_geometry.md),
[`build_e2sfca_raster_grid()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_raster_grid.md),
[`prepare_e2sfca_iso()`](https://mufflyt.github.io/twostep/reference/prepare_e2sfca_iso.md)
